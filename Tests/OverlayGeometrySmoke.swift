import CoreGraphics
import Foundation

@main
struct OverlayGeometrySmoke {
    static func main() throws {
        try assertTinySelectionKeepsCapturedAspectRatio()
        try assertSmallSelectionGetsOCRContext()
        try assertBoundaryTextCanBeIncludedOnlyWhenItBelongsToSelection()
        try assertExpandedCaptureUsesItsOwnDisplayScale()
        try assertPixelRectKeepsExactTopLeftAnchor()
        try assertTextRemovalPreservesBackgroundVariation()
        try assertTextRemovalSurvivesImperfectForegroundEstimate()
        try assertAdjacentTextDoesNotContaminateRestoration()

        print("Overlay geometry smoke test passed.")
    }

    private static func assertPixelRectKeepsExactTopLeftAnchor() throws {
        let result = OverlayGeometry.displayRect(
            forPixelRect: CGRect(x: 100.1, y: 50.1, width: 300.3, height: 100.2),
            screenshotPixelSize: CGSize(width: 1_001, height: 501),
            displayBounds: CGRect(x: 0, y: 0, width: 500, height: 250)
        )
        let expected = CGRect(
            x: 100.1 / 1_001 * 500,
            y: 50.1 / 501 * 250,
            width: 300.3 / 1_001 * 500,
            height: 100.2 / 501 * 250
        )
        guard result.approximatelyEquals(expected, tolerance: 0.001) else {
            throw TestFailure("Pixel mapping moved the OCR anchor: expected \(expected), got \(result)")
        }
    }

    private static func assertTextRemovalPreservesBackgroundVariation() throws {
        try assertDarkTextIsRemoved(
            foreground: (red: 0, green: 0, blue: 0),
            message: "Original glyph pixels were not removed"
        )
    }

    private static func assertTextRemovalSurvivesImperfectForegroundEstimate() throws {
        try assertDarkTextIsRemoved(
            foreground: (red: 1, green: 1, blue: 1),
            message: "Obvious glyph pixels survived an imperfect OCR color estimate"
        )
    }

    private static func assertDarkTextIsRemoved(
        foreground: (red: CGFloat, green: CGFloat, blue: CGFloat),
        message: String
    ) throws {
        let image = try makeGradientImageWithDarkText()
        let sourceRect = CGRect(x: 20, y: 10, width: 40, height: 20)
        let style = TextBlockVisualStyle(
            confidence: 1,
            estimatedFontSize: 12,
            foregroundRed: foreground.red,
            foregroundGreen: foreground.green,
            foregroundBlue: foreground.blue,
            foregroundLuminance: 0.2126 * foreground.red
                + 0.7152 * foreground.green
                + 0.0722 * foreground.blue,
            strokeDensity: 0.2
        )
        guard let patch = OverlayTextBackgroundRestorer.restoredPatch(
            from: image,
            pixelRect: sourceRect,
            sourceStyle: style
        ) else {
            throw TestFailure("Expected a reconstructed background patch")
        }
        let replacement = [UInt8](repeating: 7, count: patch.width * patch.height * 4)
        let pixels = try withExtendedLifetime(replacement) {
            try rgbaPixels(from: patch)
        }
        var hasDarkPixel = false
        var redValues = Set<UInt8>()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            hasDarkPixel = hasDarkPixel
                || (pixels[index] < 18 && pixels[index + 1] < 18 && pixels[index + 2] < 18)
            redValues.insert(pixels[index])
        }
        guard !hasDarkPixel else {
            throw TestFailure(message)
        }
        guard redValues.count >= 12 else {
            throw TestFailure("Background reconstruction collapsed into a flat color block")
        }
    }

    private static func assertAdjacentTextDoesNotContaminateRestoration() throws {
        let width = 80
        let height = 80
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for index in stride(from: 3, to: pixels.count, by: 4) { pixels[index] = 255 }
        func paintBlack(xRange: ClosedRange<Int>, yRange: ClosedRange<Int>) {
            for y in yRange {
                for x in xRange {
                    let index = (y * width + x) * 4
                    pixels[index] = 0
                    pixels[index + 1] = 0
                    pixels[index + 2] = 0
                }
            }
        }
        paintBlack(xRange: 30...50, yRange: 35...45)
        paintBlack(xRange: 35...38, yRange: 23...24)
        paintBlack(xRange: 35...38, yRange: 56...57)
        let image = try makeImage(width: width, height: height, pixels: pixels)
        guard let patch = OverlayTextBackgroundRestorer.restoredPatch(
            from: image,
            pixelRect: CGRect(x: 20, y: 25, width: 40, height: 30),
            sourceStyle: .unknown
        ) else {
            throw TestFailure("Expected a reconstructed patch around adjacent text")
        }
        let restored = try rgbaPixels(from: patch)
        let containsDarkStripe = stride(from: 0, to: restored.count, by: 4).contains { index in
            restored[index] < 32 && restored[index + 1] < 32 && restored[index + 2] < 32
        }
        guard !containsDarkStripe else {
            throw TestFailure("Adjacent rows contaminated the reconstructed background")
        }
    }

    private static func assertTinySelectionKeepsCapturedAspectRatio() throws {
        let screenshotSize = CGSize(width: 34, height: 16)
        let result = OverlayGeometry.resultFrame(
            screenshotPixelSize: screenshotSize,
            screenPosition: CGPoint(x: 100, y: 100),
            displayScale: 1
        )

        guard result.size == screenshotSize else {
            throw TestFailure("Expected tiny selections to preserve the selected screenshot size, got \(result.size)")
        }
        guard result.origin == CGPoint(x: 100, y: 100) else {
            throw TestFailure("Expected overlay to keep the selected top-left anchor, got \(result.origin)")
        }
    }

    private static func assertSmallSelectionGetsOCRContext() throws {
        let screen = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let selection = CGRect(x: 240, y: 310, width: 28, height: 18)
        let expanded = SelectionGeometry.expandedRect(for: selection, within: screen)
        guard expanded.minX < selection.minX,
              expanded.minY < selection.minY,
              expanded.maxX > selection.maxX,
              expanded.maxY > selection.maxY else {
            throw TestFailure("Small selections must receive OCR context padding")
        }
    }

    private static func assertBoundaryTextCanBeIncludedOnlyWhenItBelongsToSelection() throws {
        let selection = CGRect(x: 20, y: 20, width: 40, height: 20)
        guard SelectionGeometry.shouldInclude(
            CGRect(x: 18, y: 20, width: 22, height: 20),
            in: selection
        ) else {
            throw TestFailure("A word crossing the selection edge should remain eligible")
        }
        guard !SelectionGeometry.shouldInclude(
            CGRect(x: 80, y: 20, width: 22, height: 20),
            in: selection
        ) else {
            throw TestFailure("A neighboring word outside the selection must be excluded")
        }
    }

    private static func assertExpandedCaptureUsesItsOwnDisplayScale() throws {
        let originalSelection = CGRect(x: 100, y: 120, width: 80, height: 30)
        let captureRect = originalSelection.insetBy(dx: -12, dy: -12)
        let pixelSize = CGSize(width: captureRect.width * 2, height: captureRect.height * 2)
        let displayScale = SelectionGeometry.displayScale(
            forPixelSize: pixelSize,
            captureRect: captureRect
        )
        let frame = OverlayGeometry.resultFrame(
            screenshotPixelSize: pixelSize,
            screenPosition: captureRect.origin,
            displayScale: displayScale
        )
        guard abs(frame.width - captureRect.width) < 0.01,
              abs(frame.height - captureRect.height) < 0.01 else {
            throw TestFailure("Expanded capture must keep its own display size; got \(frame.size)")
        }
    }

    private static func makeGradientImageWithDarkText() throws -> CGImage {
        let width = 80
        let height = 40
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                pixels[index] = UInt8(60 + x * 2)
                pixels[index + 1] = UInt8(110 + y)
                pixels[index + 2] = 160
                pixels[index + 3] = 255
                if (18...21).contains(y), (25...54).contains(x) {
                    pixels[index] = 0
                    pixels[index + 1] = 0
                    pixels[index + 2] = 0
                }
            }
        }
        return try makeImage(width: width, height: height, pixels: pixels)
    }

    private static func rgbaPixels(from image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: &pixels,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: image.width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            throw TestFailure("Unable to read reconstructed pixels")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }

    private static func makeImage(width: Int, height: Int, pixels: [UInt8]) throws -> CGImage {
        let data = Data(pixels)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw TestFailure("Unable to create gradient test image")
        }
        return image
    }
}

private extension CGRect {
    func approximatelyEquals(_ other: CGRect, tolerance: CGFloat) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
