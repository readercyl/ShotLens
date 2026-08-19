import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import Vision
import Darwin

@main
struct ShotLensOCR {
    static func main() {
        do {
            guard CommandLine.arguments.count >= 2 else {
                throw OCRToolError.missingImagePath
            }

            let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
            let blocks = try recognizeText(
                in: imageURL,
                allowEdgeText: CommandLine.arguments.contains("--allow-edge-text")
            )
            let data = try JSONEncoder().encode(blocks)
            FileHandle.standardOutput.write(data)
            exit(0)
        } catch {
            let message = "\(error.localizedDescription)\n"
            if let data = message.data(using: .utf8) {
                FileHandle.standardError.write(data)
            }
            exit(1)
        }
    }

    private static func recognizeText(in imageURL: URL, allowEdgeText: Bool) throws -> [OCRBlockDTO] {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRToolError.unreadableImage
        }

        let originalBlocks = try recognizeTextBlocks(in: image, sourceImage: image, allowEdgeText: allowEdgeText)
        guard let enhanced = enhancedRecognitionImage(from: image) else {
            return originalBlocks
        }
        let enhancedBlocks = try recognizeTextBlocks(in: enhanced, sourceImage: image, allowEdgeText: allowEdgeText)
        return mergeRecognitionPasses(primary: originalBlocks, supplemental: enhancedBlocks)
    }

    /// 原图结果优先，增强图只补回浅色漏字；只有置信度显著更高时才替换同位置结果。
    private static func mergeRecognitionPasses(
        primary: [OCRBlockDTO],
        supplemental: [OCRBlockDTO]
    ) -> [OCRBlockDTO] {
        var merged = primary
        for candidate in supplemental {
            if let index = merged.indices.first(where: {
                merged[$0].boundingBox.rect.overlapRatio(with: candidate.boundingBox.rect) >= 0.55
            }) {
                if candidate.visualStyle.confidence >= merged[index].visualStyle.confidence + 0.08 {
                    merged[index] = candidate
                }
            } else {
                merged.append(candidate)
            }
        }
        return merged.sorted {
            let tolerance = max(6, min($0.boundingBox.height, $1.boundingBox.height) * 0.35)
            if abs($0.boundingBox.y - $1.boundingBox.y) > tolerance {
                return $0.boundingBox.y < $1.boundingBox.y
            }
            return $0.boundingBox.x < $1.boundingBox.x
        }
    }

    private static func recognizeTextBlocks(
        in recognitionImage: CGImage,
        sourceImage: CGImage,
        allowEdgeText: Bool
    ) throws -> [OCRBlockDTO] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        request.minimumTextHeight = 0.004
        request.recognitionLanguages = supportedRecognitionLanguages()
        request.customWords = [
            "AI",
            "API",
            "OCR",
            "JSON",
            "GitHub",
            "ChatGPT",
            "GPT-4o",
            "Claude",
            "Settings",
            "Search",
            "Continue",
            "Cancel",
            "Copy",
            "Save",
            "Download",
            "Upload",
            "Updated"
        ]

        let handler = VNImageRequestHandler(cgImage: recognitionImage, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        let imageSize = CGSize(width: sourceImage.width, height: sourceImage.height)
        return observations.compactMap { observation -> OCRBlockDTO? in
            guard let candidate = bestCandidate(from: observation) else { return nil }
            return textBlock(
                from: candidate,
                observation: observation,
                image: sourceImage,
                imageSize: imageSize,
                allowEdgeText: allowEdgeText
            )
        }
    }

    private static func supportedRecognitionLanguages() -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        return (try? request.supportedRecognitionLanguages()) ?? ["en-US", "zh-Hans"]
    }

    private static func bestCandidate(from observation: VNRecognizedTextObservation) -> VNRecognizedText? {
        observation.topCandidates(5)
            .filter { $0.string.hasMeaningfulOCRContent }
            .max { candidateScore($0) < candidateScore($1) }
    }

    private static func candidateScore(_ candidate: VNRecognizedText) -> Float {
        candidate.confidence
            + (candidate.string.containsHanCharacter ? 0.12 : 0)
            + (candidate.string.containsLatinLetter ? 0.03 : 0)
    }

    private static func textBlock(
        from candidate: VNRecognizedText,
        observation: VNRecognizedTextObservation,
        image: CGImage,
        imageSize: CGSize,
        allowEdgeText: Bool
    ) -> OCRBlockDTO? {
        let text = candidate.string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(
                of: #"\bGPT-4[0O]\b"#,
                with: "GPT-4o",
                options: [.regularExpression, .caseInsensitive]
            )
        guard text.hasMeaningfulOCRContent else { return nil }

        let lineBoundingBox = observation.boundingBox
            .fromVisionNormalized(to: imageSize)
            .intersection(CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
        guard !lineBoundingBox.isNull,
              lineBoundingBox.width >= 1,
              lineBoundingBox.height >= 1,
              allowEdgeText || lineBoundingBox.isSafelyInside(imageSize: imageSize) else {
            return nil
        }

        let ranges = englishRanges(in: text)
        let englishRuns = ranges.compactMap { range -> OCRRunDTO? in
            let rawRun = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            let run = rawRun
            guard run.containsLatinLetter else { return nil }
            if run.count == 1, !run.first!.isNumber, ranges.count > 1 {
                // 混合语言截图中，Vision 偶尔会把单个汉字误报成 X/#/I；
                // 独立单字不作为英文翻译目标。
                return nil
            }
            guard let normalizedRange = text.range(of: run, range: range),
                  let runBox = try? candidate.boundingBox(for: normalizedRange) else {
                return nil
            }
            let boundingBox = runBox.boundingBox
                .fromVisionNormalized(to: imageSize)
                .intersection(CGRect(x: 0, y: 0, width: imageSize.width, height: imageSize.height))
            guard !boundingBox.isNull,
                  boundingBox.width >= 1,
                  boundingBox.height >= 1 else {
                return nil
            }
            return OCRRunDTO(
                text: run,
                boundingBox: OCRRectDTO(rect: boundingBox)
            )
        }

        return OCRBlockDTO(
            text: text,
            boundingBox: OCRRectDTO(rect: lineBoundingBox),
            detectedLanguage: text.containsHanCharacter ? "mixed" : (text.containsLatinLetter ? "en" : "und"),
            visualStyle: estimateVisualStyle(
                in: image,
                boundingBox: lineBoundingBox,
                confidence: candidate.confidence
            ),
            englishRuns: englishRuns
        )
    }

    private static func englishRanges(in text: String) -> [Range<String.Index>] {
        let characters = Array(text)
        var ranges: [(Int, Int)] = []
        var start: Int?
        var end = 0

        func flush() {
            guard let start, end > start else { return }
            ranges.append((start, end))
        }

        for index in characters.indices {
            let character = characters[index]
            if character.isLatinLetter {
                if start == nil { start = index }
                end = index + 1
                continue
            }

            if start != nil, character.isNumber || "-_.,;:!?='&%+()[]#~".contains(character) {
                end = index + 1
                continue
            }

            flush()
            start = nil
            end = index + 1
        }
        flush()

        return ranges.compactMap { start, end in
            guard start < end else { return nil }
            let lower = text.index(text.startIndex, offsetBy: start)
            let upper = text.index(text.startIndex, offsetBy: end)
            let range = lower..<upper
            return String(text[range]).containsLatinLetter ? range : nil
        }
    }

    /// 轻量提高低对比度浅色字的边缘，不改变尺寸，因此坐标仍可直接映射回原截图。
    private static func enhancedRecognitionImage(from image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let colorControls = CIFilter(name: "CIColorControls"),
              let sharpen = CIFilter(name: "CISharpenLuminance") else {
            return nil
        }
        colorControls.setValue(input, forKey: kCIInputImageKey)
        colorControls.setValue(0, forKey: kCIInputSaturationKey)
        colorControls.setValue(1.35, forKey: kCIInputContrastKey)
        guard let contrasted = colorControls.outputImage else { return nil }

        sharpen.setValue(contrasted, forKey: kCIInputImageKey)
        sharpen.setValue(0.35, forKey: kCIInputSharpnessKey)
        guard let output = sharpen.outputImage else { return nil }
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(output, from: input.extent)
    }

    private static func estimateVisualStyle(
        in image: CGImage,
        boundingBox: CGRect,
        confidence: Float
    ) -> OCRStyleDTO {
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let sampleRect = boundingBox.integral.intersection(imageRect)
        guard !sampleRect.isNull,
              sampleRect.width >= 1,
              sampleRect.height >= 1,
              let crop = image.cropping(to: sampleRect) else {
            return OCRStyleDTO(confidence: confidence, estimatedFontSize: max(1, boundingBox.height))
        }

        let sampleWidth = min(72, max(1, Int(sampleRect.width.rounded(.up))))
        let sampleHeight = min(48, max(1, Int(sampleRect.height.rounded(.up))))
        var pixels = [UInt8](repeating: 0, count: sampleWidth * sampleHeight * 4)
        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let baseAddress = buffer.baseAddress,
                  let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                    data: baseAddress,
                    width: sampleWidth,
                    height: sampleHeight,
                    bitsPerComponent: 8,
                    bytesPerRow: sampleWidth * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .low
            context.draw(crop, in: CGRect(x: 0, y: 0, width: sampleWidth, height: sampleHeight))
            return true
        }

        guard drewImage else {
            return OCRStyleDTO(confidence: confidence, estimatedFontSize: max(1, boundingBox.height))
        }

        var borderLuminance: [CGFloat] = []
        var allLuminance: [CGFloat] = []
        borderLuminance.reserveCapacity(sampleWidth * 2 + sampleHeight * 2)
        allLuminance.reserveCapacity(sampleWidth * sampleHeight)

        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let index = (y * sampleWidth + x) * 4
                let alpha = pixels[index + 3]
                guard alpha > 20 else { continue }
                let luminance = Self.luminance(
                    red: pixels[index],
                    green: pixels[index + 1],
                    blue: pixels[index + 2]
                )
                allLuminance.append(luminance)
                if x == 0 || y == 0 || x == sampleWidth - 1 || y == sampleHeight - 1 {
                    borderLuminance.append(luminance)
                }
            }
        }

        let backgroundLuminance = median(borderLuminance) ?? median(allLuminance) ?? 1
        var foregroundRed: CGFloat = 0
        var foregroundGreen: CGFloat = 0
        var foregroundBlue: CGFloat = 0
        var foregroundLuminance: CGFloat = 0
        var foregroundCount: CGFloat = 0

        for y in 0..<sampleHeight {
            for x in 0..<sampleWidth {
                let index = (y * sampleWidth + x) * 4
                let alpha = pixels[index + 3]
                guard alpha > 20 else { continue }
                let red = CGFloat(pixels[index]) / 255
                let green = CGFloat(pixels[index + 1]) / 255
                let blue = CGFloat(pixels[index + 2]) / 255
                let pixelLuminance = Self.luminance(red: pixels[index], green: pixels[index + 1], blue: pixels[index + 2])
                guard abs(pixelLuminance - backgroundLuminance) >= 0.16 else { continue }

                foregroundRed += red
                foregroundGreen += green
                foregroundBlue += blue
                foregroundLuminance += pixelLuminance
                foregroundCount += 1
            }
        }

        let totalPixels = CGFloat(max(1, sampleWidth * sampleHeight))
        guard foregroundCount > 0 else {
            return OCRStyleDTO(
                confidence: confidence,
                estimatedFontSize: max(1, boundingBox.height),
                foregroundRed: backgroundLuminance,
                foregroundGreen: backgroundLuminance,
                foregroundBlue: backgroundLuminance,
                foregroundLuminance: backgroundLuminance,
                strokeDensity: 0
            )
        }

        return OCRStyleDTO(
            confidence: confidence,
            estimatedFontSize: max(1, boundingBox.height),
            foregroundRed: foregroundRed / foregroundCount,
            foregroundGreen: foregroundGreen / foregroundCount,
            foregroundBlue: foregroundBlue / foregroundCount,
            foregroundLuminance: foregroundLuminance / foregroundCount,
            strokeDensity: min(1, foregroundCount / totalPixels)
        )
    }

    private static func luminance(red: UInt8, green: UInt8, blue: UInt8) -> CGFloat {
        let r = CGFloat(red) / 255
        let g = CGFloat(green) / 255
        let b = CGFloat(blue) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    private static func median(_ values: [CGFloat]) -> CGFloat? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

}

private struct OCRBlockDTO: Encodable {
    let text: String
    let boundingBox: OCRRectDTO
    let detectedLanguage: String
    let visualStyle: OCRStyleDTO
    let englishRuns: [OCRRunDTO]
}

private struct OCRRunDTO: Encodable {
    let text: String
    let boundingBox: OCRRectDTO
}

private struct OCRStyleDTO: Encodable {
    let confidence: Float
    let estimatedFontSize: CGFloat
    let foregroundRed: CGFloat
    let foregroundGreen: CGFloat
    let foregroundBlue: CGFloat
    let foregroundLuminance: CGFloat
    let strokeDensity: CGFloat

    init(
        confidence: Float,
        estimatedFontSize: CGFloat,
        foregroundRed: CGFloat = 0,
        foregroundGreen: CGFloat = 0,
        foregroundBlue: CGFloat = 0,
        foregroundLuminance: CGFloat = -1,
        strokeDensity: CGFloat = 0
    ) {
        self.confidence = confidence
        self.estimatedFontSize = estimatedFontSize
        self.foregroundRed = foregroundRed
        self.foregroundGreen = foregroundGreen
        self.foregroundBlue = foregroundBlue
        self.foregroundLuminance = foregroundLuminance
        self.strokeDensity = strokeDensity
    }
}

private struct OCRRectDTO: Encodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    init(rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

private enum OCRToolError: LocalizedError {
    case missingImagePath
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .missingImagePath:
            return "缺少图片路径"
        case .unreadableImage:
            return "无法读取截图图片"
        }
    }
}

private extension CGRect {
    func overlapRatio(with other: CGRect) -> CGFloat {
        let intersection = intersection(other)
        guard !intersection.isNull else { return 0 }
        let minimumArea = min(width * height, other.width * other.height)
        return minimumArea > 0 ? intersection.width * intersection.height / minimumArea : 0
    }

    func fromVisionNormalized(to imageSize: CGSize) -> CGRect {
        let pixelX = origin.x * imageSize.width
        let pixelY = (1.0 - origin.y - size.height) * imageSize.height
        let pixelWidth = size.width * imageSize.width
        let pixelHeight = size.height * imageSize.height
        return CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
    }

    func isSafelyInside(imageSize: CGSize) -> Bool {
        let edgeMargin = max(1, min(imageSize.width, imageSize.height) * 0.002)
        return minX > edgeMargin
            && minY > edgeMargin
            && maxX < imageSize.width - edgeMargin
            && maxY < imageSize.height - edgeMargin
    }
}

private extension String {
    var containsLatinLetter: Bool {
        unicodeScalars.contains { scalar in
            (65...90).contains(Int(scalar.value))
                || (97...122).contains(Int(scalar.value))
                || (0x00C0...0x024F).contains(Int(scalar.value))
        }
    }

    var containsHanCharacter: Bool {
        unicodeScalars.contains { scalar in
            (0x3400...0x4DBF).contains(Int(scalar.value))
                || (0x4E00...0x9FFF).contains(Int(scalar.value))
                || (0xF900...0xFAFF).contains(Int(scalar.value))
        }
    }

    var hasMeaningfulOCRContent: Bool {
        unicodeScalars.contains(where: { CharacterSet.letters.contains($0) })
            || containsHanCharacter
            || unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) })
    }
}

private extension Character {
    var isLatinLetter: Bool {
        unicodeScalars.contains { scalar in
            (65...90).contains(Int(scalar.value))
                || (97...122).contains(Int(scalar.value))
                || (0x00C0...0x024F).contains(Int(scalar.value))
        }
    }
}
