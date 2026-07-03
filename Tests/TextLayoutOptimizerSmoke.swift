import CoreGraphics
import Foundation

@main
struct TextLayoutOptimizerSmoke {
    static func main() throws {
        try assertIsolatedShortWordSurvives()
        try assertLongerContentSurvives()
        try assertLikelyIconStillFiltersFromMultipleBlocks()

        print("Text layout optimizer smoke test passed.")
    }

    private static func assertIsolatedShortWordSurvives() throws {
        let word = TextBlock(
            text: "a",
            boundingBox: CGRect(x: 0, y: 0, width: 14, height: 14),
            detectedLanguage: "en",
            visualStyle: style(confidence: 0.3, fontSize: 12)
        )

        let result = TextLayoutOptimizer.merge([word])
        guard result.map(\.text) == ["a"] else {
            throw TestFailure("Expected an isolated short word to survive OCR layout filtering, got \(result.map(\.text))")
        }
    }

    private static func assertLongerContentSurvives() throws {
        let samples: [[TextBlock]] = [
            [block("translation", y: 0)],
            [block("This is a complete sentence.", y: 0)],
            [
                block("This is the first line of a paragraph,", y: 0),
                block("and this is the second line.", y: 24)
            ],
            [
                block("Article heading", y: 0),
                block("The first paragraph contains a complete idea.", y: 36),
                block("The second paragraph continues the article.", y: 60)
            ]
        ]

        for sample in samples {
            guard !TextLayoutOptimizer.merge(sample).isEmpty else {
                throw TestFailure("Expected word, sentence, paragraph, and article content to survive")
            }
        }
    }

    private static func assertLikelyIconStillFiltersFromMultipleBlocks() throws {
        let iconLike = TextBlock(
            text: "a",
            boundingBox: CGRect(x: 0, y: 0, width: 14, height: 14),
            detectedLanguage: "en",
            visualStyle: style(confidence: 0.3, fontSize: 12)
        )
        let label = block("Settings", y: 24)

        let result = TextLayoutOptimizer.merge([iconLike, label])
        guard result.map(\.text) == ["Settings"] else {
            throw TestFailure("Expected icon filtering to remain active in multi-block layouts, got \(result.map(\.text))")
        }
    }

    private static func block(_ text: String, y: CGFloat) -> TextBlock {
        TextBlock(
            text: text,
            boundingBox: CGRect(x: 0, y: y, width: max(80, CGFloat(text.count * 8)), height: 18),
            detectedLanguage: "en",
            visualStyle: style(confidence: 0.95, fontSize: 16)
        )
    }

    private static func style(confidence: Float, fontSize: CGFloat) -> TextBlockVisualStyle {
        TextBlockVisualStyle(
            confidence: confidence,
            estimatedFontSize: fontSize,
            foregroundRed: 0,
            foregroundGreen: 0,
            foregroundBlue: 0,
            foregroundLuminance: 0,
            strokeDensity: 0.3
        )
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
