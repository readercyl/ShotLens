import Foundation

struct LLMConnectionChecker {
    let settings: TranslationSettings

    func isAvailable() async -> Bool {
        guard settings.isLLMConfigured else {
            return false
        }

        do {
            try await LLMTranslator(settings: settings)
                .validateMicroTranslation(from: "en", to: "zh-Hans")
            return true
        } catch {
            ShotLensLogger.log("API 测试失败", error: error)
            return false
        }
    }
}
