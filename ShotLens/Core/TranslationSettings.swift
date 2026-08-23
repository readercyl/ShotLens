import Foundation
import Security

protocol TranslationSecretStore: AnyObject {
    func load() throws -> String?
    func save(_ value: String) throws
    func clear() throws
}

private final class KeychainTranslationSecretStore: TranslationSecretStore {
    private let service = "com.qingcheng.shotlens.mac"
    private let account = "translation-api-key"

    func load() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw TranslationSecretStoreError.keychain(status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func save(_ value: String) throws {
        let data = Data(value.utf8)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw TranslationSecretStoreError.keychain(addStatus) }
            return
        }
        guard status == errSecSuccess else { throw TranslationSecretStoreError.keychain(status) }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TranslationSecretStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

private enum TranslationSecretStoreError: Error, ShotLensDiagnosticError {
    case keychain(OSStatus)

    var diagnosticCode: String { "settings.keychain_error" }

    var diagnosticMetadata: [String: String] {
        switch self {
        case .keychain(let status):
            return ["error_number": String(status)]
        }
    }
}

struct TranslationSettings: Equatable {
    static let didChangeNotification = Notification.Name("ShotLensTranslationSettingsDidChange")
    static let apiEndpointKey = "ShotLens_LLM_APIEndpoint"
    static let apiKeyKey = "ShotLens_LLM_APIKey"
    static let modelKey = "ShotLens_LLM_Model"
    private static var secretStore: TranslationSecretStore = KeychainTranslationSecretStore()

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
        let apiKey = loadAPIKey(defaults: defaults)
        return TranslationSettings(
            apiEndpoint: defaults.string(forKey: apiEndpointKey) ?? "",
            apiKey: apiKey,
            model: defaults.string(forKey: modelKey) ?? ""
        )
    }

    @discardableResult
    func save() -> Bool {
        let defaults = UserDefaults.standard
        defaults.set(apiEndpoint.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.apiEndpointKey)
        defaults.set(model.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.modelKey)
        do {
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                try Self.secretStore.clear()
            } else {
                try Self.secretStore.save(key)
            }
            defaults.removeObject(forKey: Self.apiKeyKey)
        } catch {
            ShotLensLogger.event("api_key_save_failed", level: .error, stage: "settings", outcome: "failed", error: error)
            defaults.synchronize()
            return false
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        return true
    }

    @discardableResult
    static func resetSavedConfiguration() -> Bool {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: apiEndpointKey)
        defaults.removeObject(forKey: apiKeyKey)
        defaults.removeObject(forKey: modelKey)
        var clearedSecret = true
        do {
            try secretStore.clear()
        } catch {
            clearedSecret = false
            ShotLensLogger.event("api_key_clear_failed", level: .error, stage: "settings", outcome: "failed", error: error)
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
        return clearedSecret
    }

    @discardableResult
    static func clearSavedConfiguration() -> Bool {
        let defaults = UserDefaults.standard
        defaults.set("", forKey: apiEndpointKey)
        defaults.removeObject(forKey: apiKeyKey)
        defaults.set("", forKey: modelKey)
        var clearedSecret = true
        do {
            try secretStore.clear()
        } catch {
            clearedSecret = false
            ShotLensLogger.event("api_key_clear_failed", level: .error, stage: "settings", outcome: "failed", error: error)
        }
        defaults.synchronize()
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
        return clearedSecret
    }

    private var normalizedEndpointString: String {
        effectiveAPIEndpoint
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func loadAPIKey(defaults: UserDefaults) -> String {
        do {
            if let key = try secretStore.load(), !key.isEmpty {
                defaults.removeObject(forKey: apiKeyKey)
                return key
            }
        } catch {
            ShotLensLogger.event("api_key_load_failed", level: .error, stage: "settings", outcome: "failed", error: error)
        }

        let legacyKey = defaults.string(forKey: apiKeyKey) ?? ""
        guard !legacyKey.isEmpty else { return "" }
        do {
            try secretStore.save(legacyKey)
            defaults.removeObject(forKey: apiKeyKey)
        } catch {
            ShotLensLogger.event("api_key_migration_failed", level: .error, stage: "settings", outcome: "failed", error: error)
        }
        return legacyKey
    }

    static func installSecretStoreForTesting(_ store: TranslationSecretStore) {
        secretStore = store
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
