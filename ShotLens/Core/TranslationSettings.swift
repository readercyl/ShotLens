import Foundation

struct TranslationSettings {
    static let didChangeNotification = Notification.Name("ShotLensTranslationSettingsDidChange")
    static let apiEndpointKey = "ShotLens_LLM_APIEndpoint"
    static let apiKeyKey = "ShotLens_LLM_APIKey"
    static let modelKey = "ShotLens_LLM_Model"

    var apiEndpoint: String
    var apiKey: String
    var model: String

    var isLLMConfigured: Bool {
        !apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var apiAvailabilityText: String {
        isLLMConfigured ? "API 已配置" : "API 未配置"
    }

    var translationAvailabilitySummary: String {
        apiAvailabilityText
    }

    static func load() -> TranslationSettings {
        let defaults = UserDefaults.standard
        return TranslationSettings(
            apiEndpoint: defaults.string(forKey: apiEndpointKey) ?? "",
            apiKey: defaults.string(forKey: apiKeyKey) ?? "",
            model: defaults.string(forKey: modelKey) ?? "gpt-4o-mini"
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.apiEndpointKey)
        defaults.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.apiKeyKey)
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.modelKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    static func resetSavedConfiguration() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: apiEndpointKey)
        defaults.removeObject(forKey: apiKeyKey)
        defaults.removeObject(forKey: modelKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}
