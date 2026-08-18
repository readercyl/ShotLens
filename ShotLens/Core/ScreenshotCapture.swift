import AppKit
import CoreGraphics
import CoreVideo
import ImageIO
import ScreenCaptureKit

struct CapturedScreenshot {
    let image: CGImage
    let fileURL: URL
    /// 用户实际框选区域在裁剪图中的像素坐标。OCR 可使用外围上下文，
    /// 但最终只接纳与该区域相交的文字。
    let userSelectionRectInImage: CGRect
}

struct FrozenScreenshot {
    let image: CGImage
    let fileURL: URL
    let screenRect: CGRect
}

/// 截图工具。ShotLens 负责全屏蒙版和选区交互；这里在进程内捕获当前屏幕。
struct ScreenshotCapture {
    func hasScreenCaptureAccess() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    func capture(selection rect: CGRect) async throws -> CapturedScreenshot? {
        guard let frozenSnapshot = try await captureFrozenDisplay() else {
            return nil
        }
        return try crop(frozenSnapshot: frozenSnapshot, selection: rect)
    }

    func captureFrozenDisplay(containing mouseLocation: CGPoint = NSEvent.mouseLocation) async throws -> FrozenScreenshot? {
        guard let screen = screen(containing: mouseLocation) else {
            return nil
        }
        let image = try await captureDisplayImage(for: screen)
        let outputURL = temporaryPNGURL()
        try writePNG(image, to: outputURL)
        ShotLensLogger.log("冻结屏幕：捕获鼠标所在显示器 \(screen.frame)，输出 \(outputURL.path)")

        return FrozenScreenshot(
            image: image,
            fileURL: outputURL,
            screenRect: screen.frame
        )
    }

    func crop(
        frozenSnapshot: FrozenScreenshot,
        selection rect: CGRect,
        userSelection: CGRect? = nil
    ) throws -> CapturedScreenshot? {
        let scaleX = CGFloat(frozenSnapshot.image.width) / max(frozenSnapshot.screenRect.width, 1)
        let scaleY = CGFloat(frozenSnapshot.image.height) / max(frozenSnapshot.screenRect.height, 1)
        let minX = max(0, floor((rect.minX - frozenSnapshot.screenRect.minX) * scaleX))
        let maxX = min(
            CGFloat(frozenSnapshot.image.width),
            ceil((rect.maxX - frozenSnapshot.screenRect.minX) * scaleX)
        )
        let minY = max(0, floor((frozenSnapshot.screenRect.maxY - rect.maxY) * scaleY))
        let maxY = min(
            CGFloat(frozenSnapshot.image.height),
            ceil((frozenSnapshot.screenRect.maxY - rect.minY) * scaleY)
        )

        guard maxX > minX, maxY > minY else {
            return nil
        }

        let cropRect = CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
        guard let croppedImage = frozenSnapshot.image.cropping(to: cropRect) else {
            throw ScreenshotCaptureError.emptyImage
        }

        let normalizedImage = normalizedCopy(of: croppedImage) ?? croppedImage
        let outputURL = temporaryPNGURL()
        try writePNG(normalizedImage, to: outputURL)
        let selectedRect = userSelection ?? rect
        let userRectInImage = CGRect(
            x: (selectedRect.minX - rect.minX) * scaleX,
            y: (rect.maxY - selectedRect.maxY) * scaleY,
            width: selectedRect.width * scaleX,
            height: selectedRect.height * scaleY
        ).intersection(CGRect(x: 0, y: 0, width: cropRect.width, height: cropRect.height))

        return CapturedScreenshot(
            image: normalizedImage,
            fileURL: outputURL,
            userSelectionRectInImage: userRectInImage
        )
    }

    private func temporaryPNGURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotLens-\(UUID().uuidString)")
            .appendingPathExtension("png")
    }

    private func captureDisplayImage(for screen: NSScreen) async throws -> CGImage {
        guard let displayID = displayID(for: screen) else {
            throw ScreenshotCaptureError.emptyImage
        }

        let content = try await SCShareableContent.current
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw ScreenshotCaptureError.emptyImage
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        if #available(macOS 14.2, *) {
            filter.includeMenuBar = true
        }

        let displayScale = max(CGFloat(filter.pointPixelScale), screen.backingScaleFactor, 1.0)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(ceil(filter.contentRect.width * displayScale)))
        configuration.height = max(1, Int(ceil(filter.contentRect.height * displayScale)))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.queueDepth = 1
        configuration.captureResolution = .best

        let image = try await captureImage(contentFilter: filter, configuration: configuration)
        return normalizedCopy(of: image) ?? image
    }

    private func captureImage(
        contentFilter: SCContentFilter,
        configuration: SCStreamConfiguration
    ) async throws -> CGImage {
        try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(
                contentFilter: contentFilter,
                configuration: configuration
            ) { image, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let image else {
                    continuation.resume(throwing: ScreenshotCaptureError.emptyImage)
                    return
                }

                continuation.resume(returning: image)
            }
        }
    }

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return (screen.deviceDescription[key] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }

    private func screen(containing point: CGPoint) -> NSScreen? {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
    }

    private func normalizedCopy(of image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw ScreenshotCaptureError.missingOutput(path: url.path, stderr: "无法创建 PNG 写入目标")
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotCaptureError.missingOutput(path: url.path, stderr: "PNG 写入失败")
        }
    }
}

enum SelectionGeometry {
    /// 给 OCR 留出字形上下文，但保持最终归属仍由用户原始框选决定。
    static func expandedRect(for selection: CGRect, within screenRect: CGRect) -> CGRect {
        let shortestSide = min(selection.width, selection.height)
        let padding = min(24, max(8, shortestSide * 0.35))
        return selection
            .insetBy(dx: -padding, dy: -padding)
            .intersection(screenRect)
    }

    static func shouldInclude(_ candidate: CGRect, in userSelection: CGRect) -> Bool {
        guard !candidate.isNull, candidate.width > 0, candidate.height > 0 else { return false }
        let intersection = candidate.intersection(userSelection)
        guard !intersection.isNull else { return false }

        let candidateArea = max(candidate.width * candidate.height, 1)
        let overlapRatio = intersection.width * intersection.height / candidateArea
        let centerInside = userSelection.insetBy(dx: -max(2, candidate.height * 0.35), dy: -max(2, candidate.height * 0.35)).contains(candidate.mid)
        return overlapRatio >= 0.18 || centerInside
    }
}

private extension CGRect {
    var mid: CGPoint { CGPoint(x: midX, y: midY) }
}

private enum ScreenshotCaptureError: LocalizedError {
    case emptyImage
    case missingOutput(path: String, stderr: String)

    var errorDescription: String? {
        switch self {
        case .emptyImage:
            return "截图文件无法读取或内容为空"
        case .missingOutput(let path, let stderr):
            return stderr.isEmpty
                ? "截图成功但未生成输出文件：\(path)"
                : "截图成功但未生成输出文件：\(path)，stderr：\(stderr)"
        }
    }
}
