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
        !effectiveAPIEndpoint.isEmpty && !effectiveAPIKey.isEmpty
    }

    var effectiveAPIEndpoint: String {
        apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveAPIKey: String {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var effectiveModel: String {
        model.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var chatCompletionsURL: URL? {
        let endpoint = normalizedEndpointString
        guard !endpoint.isEmpty else { return nil }

        if endpoint.caseInsensitiveHasSuffixPath("/chat/completions") {
            return URL(string: endpoint)
        }
        if endpoint.caseInsensitiveHasSuffixPath("/models") {
            return URL(string: endpoint.droppingPathSuffix("/models") + "/chat/completions")
        }
        return URL(string: endpoint + "/chat/completions")
    }

    var modelsURL: URL? {
        let endpoint = normalizedEndpointString
        guard !endpoint.isEmpty else { return nil }

        if endpoint.caseInsensitiveHasSuffixPath("/models") {
            return URL(string: endpoint)
        }
        if endpoint.caseInsensitiveHasSuffixPath("/chat/completions") {
            return URL(string: endpoint.droppingPathSuffix("/chat/completions") + "/models")
        }
        return URL(string: endpoint + "/models")
    }

    var apiAvailabilityText: String {
        guard isLLMConfigured else { return "未配置" }
        return "使用自定义 API"
    }

    var translationAvailabilitySummary: String {
        apiAvailabilityText
    }

    static func load() -> TranslationSettings {
        let defaults = UserDefaults.standard
        return TranslationSettings(
            apiEndpoint: defaults.string(forKey: apiEndpointKey) ?? "",
            apiKey: defaults.string(forKey: apiKeyKey) ?? "",
            model: defaults.string(forKey: modelKey) ?? ""
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

    static func clearSavedConfiguration() {
        let defaults = UserDefaults.standard
        defaults.set("", forKey: apiEndpointKey)
        defaults.set("", forKey: apiKeyKey)
        defaults.set("", forKey: modelKey)
        defaults.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    private var normalizedEndpointString: String {
        effectiveAPIEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

}

private extension String {
    func caseInsensitiveHasSuffixPath(_ suffix: String) -> Bool {
        lowercased().hasSuffix(suffix.lowercased())
    }

    func droppingPathSuffix(_ suffix: String) -> String {
        guard caseInsensitiveHasSuffixPath(suffix) else { return self }
        return String(dropLast(suffix.count))
    }
}
