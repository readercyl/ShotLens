import Foundation
import CoreGraphics
import ImageIO
import Vision
import Darwin

@main
struct ShotLensOCR {
    static func main() {
        do {
            guard CommandLine.arguments.count == 2 else {
                throw OCRToolError.missingImagePath
            }

            let imageURL = URL(fileURLWithPath: CommandLine.arguments[1])
            let blocks = try recognizeText(in: imageURL)
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

    private static func recognizeText(in imageURL: URL) throws -> [OCRBlockDTO] {
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRToolError.unreadableImage
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.minimumTextHeight = 0
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observations = request.results else {
            return []
        }

        let imageSize = CGSize(width: image.width, height: image.height)
        return observations.compactMap { observation -> OCRBlockDTO? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let boundingBox = observation.boundingBox.fromVisionNormalized(to: imageSize)

            return OCRBlockDTO(
                text: candidate.string,
                boundingBox: OCRRectDTO(rect: boundingBox),
                detectedLanguage: detectLanguage(for: candidate.string),
                visualStyle: estimateVisualStyle(
                    in: image,
                    boundingBox: boundingBox,
                    confidence: candidate.confidence
                )
            )
        }
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

    private static func detectLanguage(for text: String) -> String {
        let scalars = text.unicodeScalars
        if scalars.contains(where: { (0x4E00...0x9FFF).contains(Int($0.value)) }) {
            return "zh-Hans"
        }

        if scalars.contains(where: { (0x3040...0x30FF).contains(Int($0.value)) }) {
            return "ja"
        }

        if scalars.contains(where: { (0xAC00...0xD7AF).contains(Int($0.value)) }) {
            return "ko"
        }

        let letters = scalars.filter { CharacterSet.letters.contains($0) }
        if !letters.isEmpty {
            let latinLetters = letters.filter { scalar in
                (65...90).contains(Int(scalar.value))
                    || (97...122).contains(Int(scalar.value))
                    || (0x00C0...0x024F).contains(Int(scalar.value))
            }
            if Double(latinLetters.count) / Double(letters.count) > 0.75 {
                return "en"
            }
        }

        return "und"
    }
}

private struct OCRBlockDTO: Encodable {
    let text: String
    let boundingBox: OCRRectDTO
    let detectedLanguage: String
    let visualStyle: OCRStyleDTO
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
    func fromVisionNormalized(to imageSize: CGSize) -> CGRect {
        let pixelX = origin.x * imageSize.width
        let pixelY = (1.0 - origin.y - size.height) * imageSize.height
        let pixelWidth = size.width * imageSize.width
        let pixelHeight = size.height * imageSize.height
        return CGRect(x: pixelX, y: pixelY, width: pixelWidth, height: pixelHeight)
    }
}
