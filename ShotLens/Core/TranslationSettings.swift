import Foundation

struct TranslationSettings {
    static let didChangeNotification = Notification.Name("ShotLensTranslationSettingsDidChange")
    static let apiEndpointKey = "ShotLens_LLM_APIEndpoint"
    static let apiKeyKey = "ShotLens_LLM_APIKey"
    static let modelKey = "ShotLens_LLM_Model"
    static let defaultAPIEndpoint = "https://api.siliconflow.cn/v1"
    static let defaultAPIKey = "sk-iiwyxcrwfaiqixpbfitsogijhfjsiolqtntqszuixgohjpnb"
    static let defaultModel = "tencent/Hunyuan-MT-7B"
    static let limitedFreeModelNotice = "混元模型当前限免，后续以服务商政策为准。"

    var apiEndpoint: String
    var apiKey: String
    var model: String

    var isLLMConfigured: Bool {
        !effectiveAPIEndpoint.isEmpty && !effectiveAPIKey.isEmpty
    }

    var usesDefaultAPIKey: Bool {
        apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var effectiveAPIEndpoint: String {
        let trimmed = apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultAPIEndpoint : trimmed
    }

    var effectiveAPIKey: String {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultAPIKey : trimmed
    }

    var effectiveModel: String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Self.defaultModel : trimmed
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
        usesDefaultAPIKey ? "使用默认福利额度" : "使用自定义 API"
    }

    var translationAvailabilitySummary: String {
        apiAvailabilityText
    }

    static func load() -> TranslationSettings {
        let defaults = UserDefaults.standard
        return TranslationSettings(
            apiEndpoint: defaultedValue(defaults.string(forKey: apiEndpointKey), fallback: defaultAPIEndpoint),
            apiKey: defaults.string(forKey: apiKeyKey) ?? "",
            model: defaultedValue(defaults.string(forKey: modelKey), fallback: defaultModel)
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

    private var normalizedEndpointString: String {
        effectiveAPIEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func defaultedValue(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
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
