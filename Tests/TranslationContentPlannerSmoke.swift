import CoreGraphics
import Foundation

@main
struct TranslationContentPlannerSmoke {
    static func main() throws {
        try assertChineseOnlyIsExcluded()
        try assertMixedTextOnlyKeepsEnglishRuns()
        try assertEnglishOnlyStaysSingleItem()
        try assertIsolatedEnglishPhraseStaysLocal()
        try assertLightMixedContentReflowsAsOneSemanticBlock()
        try assertChineseDominantContentOnlyReplacesEnglishRuns()
        try assertSeparatedEnglishRunsDoNotCoverProtectedText()
        try assertPartialTranslationsKeepIndependentBlocks()
        try assertWrappedHeadingAndParagraphFormSemanticBlocks()
        try assertColumnsStayIndependent()
        try assertSentenceContinuationMergesWithoutAbsorbingNearbyLegend()
        try assertNearbyBadgeStaysIndependent()
        print("Translation content planner smoke test passed.")
    }

    private static func assertChineseOnlyIsExcluded() throws {
        let plan = TranslationContentPlan.make(from: [block("已经是中文")])
        guard plan.sourceTexts.isEmpty,
              plan.applying([])?.isEmpty == true else {
            throw TestFailure("Chinese-only blocks must not be sent or covered")
        }
    }

    private static func assertMixedTextOnlyKeepsEnglishRuns() throws {
        let plan = TranslationContentPlan.make(from: [
            block("English", x: 80, y: 20, width: 120),
            block("More", x: 250, y: 20, width: 80)
        ])
        guard plan.sourceTexts == ["English", "More"],
              plan.applying(["英语", "更多"])?.map(\.translatedText) == ["英语", "更多"] else {
            throw TestFailure("Mixed-language selection must send and cover English runs only: \(plan.sourceTexts)")
        }
    }

    private static func assertEnglishOnlyStaysSingleItem() throws {
        let plan = TranslationContentPlan.make(from: [block("  Open settings  ")])
        guard plan.sourceTexts == ["Open settings"],
              plan.applying(["打开设置"])?.map(\.translatedText) == ["打开设置"] else {
            throw TestFailure("English-only block should remain one trimmed semantic item")
        }
    }

    private static func assertIsolatedEnglishPhraseStaysLocal() throws {
        let source = block(
            "Open settings",
            width: 140,
            englishRuns: [
                run("Open", x: 10, width: 42),
                run("settings", x: 58, width: 72)
            ]
        )
        let plan = TranslationContentPlan.make(from: [source])
        let translated = plan.applying(["打开设置"])
        guard plan.sourceTexts == ["Open settings"],
              translated?.first?.original.boundingBox == CGRect(x: 10, y: 10, width: 120, height: 24) else {
            throw TestFailure("Isolated English phrase should stay localized: \(plan.sourceTexts)")
        }
    }

    private static func assertLightMixedContentReflowsAsOneSemanticBlock() throws {
        let sourceText = "AI 模型 recommendations for teams"
        let source = block(
            sourceText,
            width: 360,
            englishRuns: [
                run("AI", x: 10, width: 24),
                run("recommendations", x: 80, width: 130),
                run("for", x: 218, width: 30),
                run("teams", x: 256, width: 54)
            ]
        )
        let plan = TranslationContentPlan.make(from: [source])
        guard plan.sourceTexts == [sourceText],
              plan.applying(["AI 模型团队推荐方案"])?.first?.original.boundingBox == source.boundingBox else {
            throw TestFailure("Light mixed content should be semantically reflowed as one block: \(plan.sourceTexts)")
        }
    }

    private static func assertChineseDominantContentOnlyReplacesEnglishRuns() throws {
        let source = block(
            "请点击 Settings 打开设置页面",
            width: 300,
            englishRuns: [run("Settings", x: 88, width: 76)]
        )
        let plan = TranslationContentPlan.make(from: [source])
        guard plan.sourceTexts == ["Settings"],
              plan.applying(["设置"])?.first?.original.boundingBox == CGRect(x: 88, y: 10, width: 76, height: 24) else {
            throw TestFailure("Chinese-dominant content should only replace English runs: \(plan.sourceTexts)")
        }
    }

    private static func assertSeparatedEnglishRunsDoNotCoverProtectedText() throws {
        let source = block(
            "请点击 Open 中文内容 Settings 打开页面",
            width: 360,
            englishRuns: [
                run("Open", x: 70, width: 42),
                run("Settings", x: 220, width: 76)
            ]
        )
        let plan = TranslationContentPlan.make(from: [source])
        guard plan.sourceTexts == ["Open", "Settings"] else {
            throw TestFailure("Separated English runs must remain independent: \(plan.sourceTexts)")
        }
    }

    private static func assertPartialTranslationsKeepIndependentBlocks() throws {
        let plan = TranslationContentPlan.make(from: [
            block("Release update"),
            block("Page title"),
            block("Feature description")
        ])
        let translated = plan.applyingAvailable(["版本更新", nil, "功能说明"])
        guard translated?.map(\.translatedText) == ["版本更新", "功能说明"] else {
            throw TestFailure("Unavailable items must not discard independent successful blocks")
        }
    }

    private static func assertWrappedHeadingAndParagraphFormSemanticBlocks() throws {
        let grouped = SemanticTextGrouper.merge([
            block("Independent", x: 16, y: 63, width: 863, height: 159),
            block("analysis of AI", x: 17, y: 220, width: 928, height: 166),
            block("Understand the AI landscape to choose the best", x: 22, y: 404, width: 800, height: 36),
            block("model and provider for your use case", x: 20, y: 452, width: 615, height: 51)
        ])
        guard grouped.map(\.text) == [
            "Independent analysis of AI",
            "Understand the AI landscape to choose the best model and provider for your use case"
        ] else {
            throw TestFailure("Wrapped semantic regions were not reconstructed: \(grouped.map(\.text))")
        }
    }

    private static func assertColumnsStayIndependent() throws {
        let grouped = SemanticTextGrouper.merge([
            block("Personalized", x: 48, y: 122, width: 200, height: 32),
            block("Explore agents", x: 516, y: 122, width: 226, height: 37),
            block("Explore premium", x: 980, y: 122, width: 268, height: 38),
            block("model", x: 50, y: 178, width: 98, height: 32),
            block("for general work", x: 512, y: 178, width: 262, height: 36),
            block("plans", x: 976, y: 178, width: 88, height: 38),
            block("recommender", x: 48, y: 234, width: 218, height: 32)
        ])
        guard grouped.map(\.text) == [
            "Personalized model recommender",
            "Explore agents for general work",
            "Explore premium plans"
        ] else {
            throw TestFailure("Independent columns were merged or reordered: \(grouped.map(\.text))")
        }
    }

    private static func assertSentenceContinuationMergesWithoutAbsorbingNearbyLegend() throws {
        let grouped = SemanticTextGrouper.merge([
            block("Explore agents", x: 512, y: 122, width: 230, height: 37),
            block("for general work,", x: 512, y: 178, width: 260, height: 36),
            block("coding, customer", x: 512, y: 234, width: 250, height: 36),
            block("support, and", x: 512, y: 290, width: 210, height: 36),
            block("more", x: 514, y: 348, width: 84, height: 24),
            block("Estimate (independent evaluation forthcoming)", x: 28, y: 406, width: 658, height: 30),
            block("Proprietary", x: 58, y: 450, width: 159, height: 41),
            block("Open Weights", x: 247, y: 450, width: 200, height: 41)
        ])
        guard grouped.map(\.text) == [
            "Explore agents for general work, coding, customer support, and more",
            "Estimate (independent evaluation forthcoming)",
            "Proprietary",
            "Open Weights"
        ] else {
            throw TestFailure("Sentence continuation or neighboring labels were grouped incorrectly: \(grouped.map(\.text))")
        }
    }

    private static func assertNearbyBadgeStaysIndependent() throws {
        let grouped = SemanticTextGrouper.merge([
            block("Intelligence", x: 88, y: 28, width: 294, height: 44),
            block("Updated", x: 408, y: 28, width: 128, height: 44),
            block("GDPval-", x: 80, y: 120, width: 120, height: 30),
            block("AA v2", x: 220, y: 120, width: 80, height: 30)
        ])
        guard grouped.map(\.text) == ["Intelligence", "Updated", "GDPval- AA v2"] else {
            throw TestFailure("Nearby badges or continued identifiers were grouped incorrectly: \(grouped.map(\.text))")
        }
    }

    private static func block(
        _ text: String,
        x: CGFloat = 10,
        y: CGFloat = 10,
        width: CGFloat = 200,
        height: CGFloat = 24,
        englishRuns: [TextRun] = []
    ) -> TextBlock {
        TextBlock(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: height),
            detectedLanguage: "und",
            englishRuns: englishRuns
        )
    }

    private static func run(
        _ text: String,
        x: CGFloat,
        y: CGFloat = 10,
        width: CGFloat,
        height: CGFloat = 24
    ) -> TextRun {
        TextRun(text: text, boundingBox: CGRect(x: x, y: y, width: width, height: height))
    }
}

private struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
