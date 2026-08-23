import CoreGraphics
import Foundation
import AppKit

@main
struct OverlayGeometrySmoke {
    static func main() throws {
        try assertTinySelectionKeepsCapturedAspectRatio()
        try assertTinySelectionKeepsReadableTranslationRect()
        try assertSmallSelectionGetsOCRContext()
        try assertBoundaryTextCanBeIncludedOnlyWhenItBelongsToSelection()
        try assertExpandedCaptureUsesItsOwnDisplayScale()
        try assertOCRCoordinatesMapBackToDisplaySelection()
        try assertPixelRectKeepsExactTopLeftAnchor()
        try assertTextRemovalPreservesBackgroundVariation()
        try assertTextRemovalSurvivesImperfectForegroundEstimate()
        try assertAdjacentTextDoesNotContaminateRestoration()
        try assertSemanticBlocksShareFullCanvasFlow()
        try assertSeparatedColumnsKeepIndependentFlows()
        try assertLongTranslationIsMeasuredAgainstWholeCanvas()
        try assertShortContentStaysAnchored()
        try assertLongContentUsesStructuredReflow()
        try assertStatusTitleFitsBesideToggleButton()

        print("Overlay geometry smoke test passed.")
    }

    private static func assertStatusTitleFitsBesideToggleButton() throws {
        let title = "翻译完成"
        let titleWidth = (title as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium)
        ]).width
        let actionWidth: CGFloat = 66
        let size = OverlayStatusGeometry.preferredSize(
            titleWidth: titleWidth,
            detailWidth: 0,
            actionWidth: actionWidth,
            hasDetail: false
        )
        let actionFrame = CGRect(
            x: size.width - actionWidth - 8,
            y: 2,
            width: actionWidth,
            height: 28
        )
        let textRect = OverlayStatusGeometry.textRect(
            in: CGRect(origin: .zero, size: size),
            actionFrame: actionFrame
        )

        guard textRect.width >= ceil(titleWidth) else {
            throw TestFailure("Translation status title is clipped beside its toggle button: \(textRect.width) < \(titleWidth)")
        }
    }

    private static func assertSemanticBlocksShareFullCanvasFlow() throws {
        let first = translatedBlock("第一段译文", rect: CGRect(x: 20, y: 20, width: 900, height: 24))
        let second = translatedBlock("第二段译文", rect: CGRect(x: 20, y: 260, width: 760, height: 24))
        let canvas = CGRect(x: 0, y: 0, width: 1_000, height: 400)
        let flows = OverlayTranslationLayout.makeFlows(items: [
            OverlayTranslationLayoutItem(block: second, displayRect: CGRect(x: 20, y: 260, width: 760, height: 24)),
            OverlayTranslationLayoutItem(block: first, displayRect: CGRect(x: 20, y: 20, width: 900, height: 24))
        ], canvas: canvas)
        let renderedTexts = flows.reduce(into: [String]()) { result, flow in
            result.append(contentsOf: flow.items.map(\.block.translatedText))
        }

        guard flows.count == 2,
              renderedTexts == ["第一段译文", "第二段译文"],
              flows.allSatisfy({ $0.layoutRect.width == canvas.width - 32 }),
              flows[1].layoutRect.minY < 260,
              flows[0].layoutRect.maxY <= flows[1].layoutRect.minY else {
            throw TestFailure("Semantic blocks must keep structure while using allocated result-window regions: \(flows)")
        }
    }

    private static func assertSeparatedColumnsKeepIndependentFlows() throws {
        let left = translatedBlock("左栏", rect: CGRect(x: 20, y: 40, width: 300, height: 24))
        let right = translatedBlock("右栏", rect: CGRect(x: 650, y: 40, width: 300, height: 24))
        let canvas = CGRect(x: 0, y: 0, width: 1_000, height: 300)
        let flows = OverlayTranslationLayout.makeFlows(items: [
            OverlayTranslationLayoutItem(block: left, displayRect: CGRect(x: 20, y: 40, width: 300, height: 24)),
            OverlayTranslationLayoutItem(block: right, displayRect: CGRect(x: 650, y: 40, width: 300, height: 24))
        ], canvas: canvas)

        guard flows.count == 2,
              flows[0].layoutRect.maxX <= flows[1].layoutRect.minX,
              flows.allSatisfy({ $0.layoutRect.minY == 36 }),
              flows.allSatisfy({ $0.layoutRect.maxY == canvas.height - 16 }) else {
            throw TestFailure("Separated columns must keep independent anchored flows: \(flows)")
        }
    }

    private static func assertLongTranslationIsMeasuredAgainstWholeCanvas() throws {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineBreakMode = .byCharWrapping
        paragraphStyle.paragraphSpacing = 8
        let text = String(repeating: "这是一段需要完整显示的长译文。", count: 180)
        let measurement = OverlayTranslationTextFit.measure(
            text: text,
            in: CGRect(x: 16, y: 16, width: 968, height: 368),
            targetSize: 22,
            paragraphStyle: paragraphStyle,
            minimumSize: 0.25
        )

        guard measurement.fits,
              measurement.requiredSize.height <= measurement.availableSize.height + 0.75,
              measurement.font.pointSize <= 22 else {
            throw TestFailure("Long translation must be measured and fit before drawing: \(measurement)")
        }
    }

    private static func assertShortContentStaysAnchored() throws {
        let items = [
            OverlayTranslationLayoutItem(
                block: translatedBlock("标题", rect: CGRect(x: 24, y: 42, width: 160, height: 28)),
                displayRect: CGRect(x: 24, y: 42, width: 160, height: 28)
            ),
            OverlayTranslationLayoutItem(
                block: translatedBlock("标签", rect: CGRect(x: 720, y: 42, width: 120, height: 28)),
                displayRect: CGRect(x: 720, y: 42, width: 120, height: 28)
            ),
            OverlayTranslationLayoutItem(
                block: translatedBlock("下一行", rect: CGRect(x: 24, y: 78, width: 160, height: 28)),
                displayRect: CGRect(x: 24, y: 78, width: 160, height: 28)
            )
        ]
        let canvas = CGRect(x: 0, y: 0, width: 1_000, height: 400)
        guard OverlayTranslationLayout.renderMode(for: items, canvas: canvas) == .anchored else {
            throw TestFailure("Short labels must keep the anchored rendering mode")
        }
        let rects = OverlayTranslationLayout.anchoredRects(for: items, canvas: canvas)
        guard rects.count == 3,
              rects[0].minY == 42,
              rects[1].minY == 42,
              rects[2].minY == 78,
              rects[0].height >= 28,
              rects[1].height >= 28,
              rects[0].width >= 160,
              rects[1].width >= 120,
              rects[0].maxX < rects[1].minX else {
            throw TestFailure("Short content must preserve its source row and columns: \(rects)")
        }
    }

    private static func assertLongContentUsesStructuredReflow() throws {
        let longText = String(repeating: "这是一段需要整体排版的长文本。", count: 30)
        let item = OverlayTranslationLayoutItem(
            block: translatedBlock(longText, rect: CGRect(x: 24, y: 120, width: 900, height: 80)),
            displayRect: CGRect(x: 24, y: 120, width: 900, height: 80)
        )
        let mode = OverlayTranslationLayout.renderMode(
            for: [item],
            canvas: CGRect(x: 0, y: 0, width: 1_000, height: 400)
        )
        guard mode == .structured else {
            throw TestFailure("Long paragraphs must use structured reflow")
        }
    }

    private static func translatedBlock(_ text: String, rect: CGRect) -> TranslatedBlock {
        TranslatedBlock(
            original: TextBlock(
                text: "source",
                boundingBox: rect,
                detectedLanguage: "en"
            ),
            translatedText: text
        )
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

    private static func assertTinySelectionKeepsReadableTranslationRect() throws {
        let canvas = CGRect(x: 0, y: 0, width: 80, height: 24)
        let item = OverlayTranslationLayoutItem(
            block: translatedBlock("猫", rect: canvas),
            displayRect: canvas
        )
        let rects = OverlayTranslationLayout.anchoredRects(for: [item], canvas: canvas)
        guard rects.count == 1,
              rects[0].width >= 60,
              rects[0].height >= 18 else {
            throw TestFailure("Tiny word selections must keep a readable translation rectangle: \(rects)")
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

    private static func assertOCRCoordinatesMapBackToDisplaySelection() throws {
        let block = TextBlock(
            text: "English",
            boundingBox: CGRect(x: 32, y: 24, width: 40, height: 12),
            detectedLanguage: "en"
        )
        let mapped = SelectionGeometry.mapOCRBlockToDisplay(
            block,
            userSelectionRectInOCR: CGRect(x: 20, y: 16, width: 120, height: 60),
            displayPixelSize: CGSize(width: 120, height: 60)
        )
        guard mapped?.boundingBox == CGRect(x: 12, y: 8, width: 40, height: 12) else {
            throw TestFailure("OCR coordinates were not mapped back to the original selection: \(String(describing: mapped?.boundingBox))")
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
