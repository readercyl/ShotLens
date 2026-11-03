import CoreGraphics
import Foundation

@main
struct OCRPostProcessingSmoke {
    static func main() throws {
        let peers = ["Leaderboard", "Market Share", "Languages"].enumerated().map { i, text in
            make(text, x: 138, y: CGFloat(i * 100), width: 160, height: 30,
                 runs: [(text, 138)])
        }
        let iconRows = [
            make("LI Top Models", x: 92, y: 350, width: 202, height: 30, runs: [("LI", 92), ("Top", 133)]),
            make("D Open / Closed", x: 96, y: 400, width: 240, height: 30, runs: [("Open", 131)]),
            make("‹≥ Programming", x: 88, y: 450, width: 232, height: 30, runs: [("Programming", 130)]),
            make("O Open/ Closed", x: 88, y: 500, width: 232, height: 30, runs: [("Open", 130)])
        ]
        let cleaned = ShotLensOCR.removeAlignedIconPrefixes(peers + iconRows)
        guard cleaned.suffix(4).map(\.text) == ["Top Models", "Open / Closed", "Programming", "Open/ Closed"] else {
            throw Failure("Aligned icon misreads were not removed: \(cleaned.map(\.text))")
        }
        let genuine = make("O Ring", x: 138, y: 550, width: 100, height: 30, runs: [("O", 138), ("Ring", 165)])
        guard ShotLensOCR.removeAlignedIconPrefixes(peers + [genuine]).last?.text == "O Ring" else {
            throw Failure("A genuine aligned single-letter word must survive")
        }
        let duplicates = [
            make("Images", x: 138, y: 500, width: 102, height: 35, runs: []),
            make("Images", x: 126, y: 511, width: 112, height: 25, runs: []),
            make("Images", x: 138, y: 600, width: 102, height: 35, runs: [])
        ]
        let unique = ShotLensOCR.deduplicateSameText(duplicates)
        guard unique.count == 2, unique[0].boundingBox.rect.minX == 138, unique[1].boundingBox.rect.minY == 600 else {
            throw Failure("Overlapping duplicate OCR passes must merge, distinct repeated labels must survive")
        }
        let canvas = CGContext(data: nil, width: 220, height: 220, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        canvas.setFillColor(CGColor(gray: 1, alpha: 1))
        canvas.fill(CGRect(x: 0, y: 0, width: 220, height: 220))
        canvas.setFillColor(CGColor(gray: 0, alpha: 1))
        canvas.fill(CGRect(x: 10, y: 220 - 160 - 20, width: 20, height: 14))
        canvas.fill(CGRect(x: 60, y: 220 - 160 - 20, width: 70, height: 14))
        let image = canvas.makeImage()!
        let aligned = (0..<3).map { i in make("Label", x: 60, y: CGFloat(i * 50), width: 70, height: 24, runs: []) }
        let withIcon = make("Tool Calls", x: 10, y: 160, width: 120, height: 24, runs: [("Tool", 10)])
        let refined = ShotLensOCR.correctAlignedTextBounds(aligned + [withIcon], image: image)
        guard refined.last!.boundingBox.rect.minX >= 55 else {
            throw Failure("An icon separated from an aligned text column must stay outside the text rectangle")
        }
        let continuousCanvas = CGContext(data: nil, width: 220, height: 220, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        continuousCanvas.setFillColor(CGColor(gray: 1, alpha: 1))
        continuousCanvas.fill(CGRect(x: 0, y: 0, width: 220, height: 220))
        continuousCanvas.setFillColor(CGColor(gray: 0, alpha: 1))
        continuousCanvas.fill(CGRect(x: 10, y: 220 - 160 - 20, width: 120, height: 14))
        let continuous = ShotLensOCR.correctAlignedTextBounds(aligned + [withIcon], image: continuousCanvas.makeImage()!)
        guard continuous.last!.boundingBox.rect.minX == 10 else {
            throw Failure("Aligned neighbors must not trim continuous genuine text")
        }
        print("OCR post-processing smoke test passed.")
    }

    private static func make(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat,
                             runs: [(String, CGFloat)]) -> OCRBlockDTO {
        let box = CGRect(x: x, y: y, width: width, height: height)
        return OCRBlockDTO(text: text, boundingBox: OCRRectDTO(rect: box), detectedLanguage: "en",
                           visualStyle: OCRStyleDTO(confidence: 1, estimatedFontSize: height),
                           englishRuns: runs.map { OCRRunDTO(text: $0.0, boundingBox: OCRRectDTO(rect: CGRect(x: $0.1, y: y, width: 30, height: height))) },
                           selectableRuns: [])
    }
}

private struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
