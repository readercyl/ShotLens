import Foundation

struct LLMConnectionChecker {
    let settings: TranslationSettings

    func isAvailable() async -> Bool {
        guard settings.isLLMConfigured else {
            return false
        }

        do {
            try await LLMTranslator(settings: settings)
                .validateTranslationFormat(from: "en", to: "zh-Hans")
            return true
        } catch {
            return false
        }
    }
}
