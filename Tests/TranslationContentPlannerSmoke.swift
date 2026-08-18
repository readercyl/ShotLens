import CoreGraphics
import Foundation

@main
struct TranslationContentPlannerSmoke {
    static func main() throws {
        try assertChineseOnlyIsExcluded()
        try assertMixedTextOnlyKeepsEnglishRuns()
        try assertEnglishOnlyStaysSingleItem()
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
        height: CGFloat = 24
    ) -> TextBlock {
        TextBlock(
            text: text,
            boundingBox: CGRect(x: x, y: y, width: width, height: height),
            detectedLanguage: "und"
        )
    }
}

private struct TestFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
