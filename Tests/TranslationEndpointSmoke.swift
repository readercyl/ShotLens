import Foundation

@main
struct TranslationEndpointSmoke {
    static func main() async throws {
        URLProtocol.registerClass(MockOpenAIProtocol.self)
        defer { URLProtocol.unregisterClass(MockOpenAIProtocol.self) }

        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions"
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1/",
            expectedPath: "/v1/chat/completions"
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1/chat/completions",
            expectedPath: "/v1/chat/completions"
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: "1. 你好\n2. 世界"
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: "0: 你好\n1: 世界"
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: #"["你好","世界"]"#
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: #"{"translations":["你好","世界"]}"#
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: #"{"0":"你好","1":"世界"}"#
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: #"[{"index":0,"translation":"你好"},{"index":1,"translation":"世界"}]"#
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: "```json\n[\"你好\",\"世界\"]\n```"
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: #"[ "{\"编码索引\"; \"Coding Index\"}", "代理指数" ]"#,
            input: ["Coding Index", "Agentic Index"],
            expected: ["编码索引", "代理指数"]
        )
        try await assertTranslates(
            endpoint: "https://shotlens-test.local/v1",
            expectedPath: "/v1/chat/completions",
            assistantContent: "你好\n世界"
        )
        try await assertSingleBlockPlainTextParses()
        try await assertSingleBlockExplanationParses()
        try await assertSingleBlockProtocolNoiseIsFiltered()
        try await assertSingleBlockControlTokensAreFiltered()
        try await assertSingleBlockHTTPHeadersAreFiltered()
        try await assertUnchangedSingleEnglishWordUsesLocalFallback()
        try await assertCommonShortUIWordUsesLocalFallback()
        try await assertEchoedRepairPromptDoesNotRenderAsTranslation()
        try await assertLabeledSingleTranslationExtractsChinese()
        try await assertAbbreviationUsesSurroundingContext()
        try await assertArrowOutputAvoidsRepairRequest()
        try await assertTypicalLargeSelectionStaysSingleRequest()
        try await assertPolicyLikeBatchOutputDoesNotSpendRepairRequest()
        try await assertRepairFailureDoesNotFanOutRequests()
        try await assertEmptySavedSettingsUseDefaultAPI()
        try await assertDefaultFallbackForcesBuiltInEndpointAndModel()
        try await assertCustomSavedSettingsSurviveLoad()
        try await assertClearSavedSettingsDisableDefaultAPI()
        try await assertConnectionCheckUsesChatCompletions()
        try await assertConnectionCheckAcceptsPlainTextMicroTranslation()
        try await assertConnectionCheckAcceptsMalformedTranslationContent()
        try await assertConnectionCheckRejectsHTTPError()
        try await assertConnectionCheckMarksRateLimitTransient()

        print("Translation endpoint smoke test passed.")
    }

    private static func assertTranslates(
        endpoint: String,
        expectedPath: String,
        assistantContent: String = "0\t你好\n1\t世界",
        input: [String] = ["Hello", "World"],
        expected: [String] = ["你好", "世界"]
    ) async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = assistantContent

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: endpoint,
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(input, from: "en", to: "zh-Hans")
        guard result == expected else {
            throw TestFailure("Unexpected translations for \(endpoint): \(result)")
        }

        guard MockOpenAIProtocol.requestedPaths == [expectedPath] else {
            throw TestFailure("Expected request path \(expectedPath), got \(MockOpenAIProtocol.requestedPaths)")
        }
    }

    private static func assertEmptySavedSettingsUseDefaultAPI() async throws {
        let defaults = UserDefaults.standard
        let originalEndpoint = defaults.object(forKey: TranslationSettings.apiEndpointKey)
        let originalKey = defaults.object(forKey: TranslationSettings.apiKeyKey)
        let originalModel = defaults.object(forKey: TranslationSettings.modelKey)
        let originalFallback = defaults.object(forKey: TranslationSettings.defaultFallbackEnabledKey)
        defer {
            restore(originalEndpoint, forKey: TranslationSettings.apiEndpointKey)
            restore(originalKey, forKey: TranslationSettings.apiKeyKey)
            restore(originalModel, forKey: TranslationSettings.modelKey)
            restore(originalFallback, forKey: TranslationSettings.defaultFallbackEnabledKey)
        }

        TranslationSettings.resetSavedConfiguration()

        let settings = TranslationSettings.load()
        guard settings.apiEndpoint.isEmpty else {
            throw TestFailure("Expected default endpoint to stay out of the editable field")
        }
        guard settings.apiKey.isEmpty, settings.usesDefaultAPIKey else {
            throw TestFailure("Expected saved API key to stay hidden while using default fallback")
        }
        guard settings.model.isEmpty else {
            throw TestFailure("Expected default model to stay out of the editable field")
        }
        guard settings.effectiveAPIEndpoint == TranslationSettings.defaultAPIEndpoint,
              settings.effectiveModel == TranslationSettings.defaultModel else {
            throw TestFailure("Expected hidden default endpoint and model to remain effective")
        }

        MockOpenAIProtocol.reset()
        let result = try await LLMTranslator(settings: settings)
            .translate(["Hello", "World"], from: "en", to: "zh-Hans")
        guard result == ["你好", "世界"] else {
            throw TestFailure("Unexpected translations with default settings: \(result)")
        }
        guard MockOpenAIProtocol.requestedHosts == ["api.siliconflow.cn"],
              MockOpenAIProtocol.requestedPaths == ["/v1/chat/completions"] else {
            throw TestFailure("Expected default SiliconFlow chat completions request, got \(MockOpenAIProtocol.requestedHosts) \(MockOpenAIProtocol.requestedPaths)")
        }
        guard MockOpenAIProtocol.authorizationHeaders == ["Bearer \(TranslationSettings.defaultAPIKey)"] else {
            throw TestFailure("Expected translator to use hidden default API key")
        }
        let firstBody = MockOpenAIProtocol.requestBodies.first ?? ""
        guard firstBody.contains("Hunyuan-MT-7B") else {
            throw TestFailure("Expected translator payload to include default model, got: \(firstBody)")
        }
    }

    private static func assertDefaultFallbackForcesBuiltInEndpointAndModel() async throws {
        let settings = TranslationSettings(
            apiEndpoint: "https://unexpected.example/v1",
            apiKey: "",
            model: "unexpected-model",
            defaultFallbackEnabled: true
        )

        guard settings.usesDefaultAPIKey,
              settings.effectiveAPIEndpoint == TranslationSettings.defaultAPIEndpoint,
              settings.effectiveModel == TranslationSettings.defaultModel else {
            throw TestFailure("Expected default fallback to ignore saved endpoint and model overrides")
        }
    }

    private static func assertCustomSavedSettingsSurviveLoad() async throws {
        let defaults = UserDefaults.standard
        let originalEndpoint = defaults.object(forKey: TranslationSettings.apiEndpointKey)
        let originalKey = defaults.object(forKey: TranslationSettings.apiKeyKey)
        let originalModel = defaults.object(forKey: TranslationSettings.modelKey)
        let originalFallback = defaults.object(forKey: TranslationSettings.defaultFallbackEnabledKey)
        defer {
            restore(originalEndpoint, forKey: TranslationSettings.apiEndpointKey)
            restore(originalKey, forKey: TranslationSettings.apiKeyKey)
            restore(originalModel, forKey: TranslationSettings.modelKey)
            restore(originalFallback, forKey: TranslationSettings.defaultFallbackEnabledKey)
        }

        TranslationSettings(
            apiEndpoint: "https://custom.example/v1",
            apiKey: "custom-key",
            model: "custom-model",
            defaultFallbackEnabled: false
        ).save()

        let loaded = TranslationSettings.load()
        guard loaded.apiEndpoint == "https://custom.example/v1",
              loaded.apiKey == "custom-key",
              loaded.model == "custom-model",
              loaded.effectiveAPIEndpoint == "https://custom.example/v1",
              loaded.effectiveAPIKey == "custom-key",
              loaded.effectiveModel == "custom-model",
              !loaded.usesDefaultAPIKey else {
            throw TestFailure("Expected custom API settings to survive load, got \(loaded)")
        }
    }

    private static func assertClearSavedSettingsDisableDefaultAPI() async throws {
        let defaults = UserDefaults.standard
        let originalEndpoint = defaults.object(forKey: TranslationSettings.apiEndpointKey)
        let originalKey = defaults.object(forKey: TranslationSettings.apiKeyKey)
        let originalModel = defaults.object(forKey: TranslationSettings.modelKey)
        let originalFallback = defaults.object(forKey: TranslationSettings.defaultFallbackEnabledKey)
        defer {
            restore(originalEndpoint, forKey: TranslationSettings.apiEndpointKey)
            restore(originalKey, forKey: TranslationSettings.apiKeyKey)
            restore(originalModel, forKey: TranslationSettings.modelKey)
            restore(originalFallback, forKey: TranslationSettings.defaultFallbackEnabledKey)
        }

        TranslationSettings.clearSavedConfiguration()
        let cleared = TranslationSettings.load()
        guard !cleared.defaultFallbackEnabled,
              cleared.apiEndpoint.isEmpty,
              cleared.apiKey.isEmpty,
              cleared.model.isEmpty,
              !cleared.isLLMConfigured else {
            throw TestFailure("Expected clear to disable default fallback, got \(cleared)")
        }

        TranslationSettings.resetSavedConfiguration()
        let restored = TranslationSettings.load()
        guard restored.defaultFallbackEnabled,
              restored.usesDefaultAPIKey,
              restored.isLLMConfigured,
              restored.effectiveAPIEndpoint == TranslationSettings.defaultAPIEndpoint,
              restored.effectiveModel == TranslationSettings.defaultModel else {
            throw TestFailure("Expected reset to restore default fallback, got \(restored)")
        }
    }

    private static func assertConnectionCheckUsesChatCompletions() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "你好"
        MockOpenAIProtocol.chatStatusCode = 200
        MockOpenAIProtocol.modelsStatusCode = 404

        let checker = LLMConnectionChecker(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let isAvailable = await checker.isAvailable()
        guard isAvailable else {
            throw TestFailure("Expected chat-completions connection check to pass when /models is unavailable")
        }

        guard MockOpenAIProtocol.requestedPaths == ["/v1/chat/completions"] else {
            throw TestFailure("Expected connection check to use chat completions, got \(MockOpenAIProtocol.requestedPaths)")
        }
        let body = MockOpenAIProtocol.requestBodies.first ?? ""
        guard body.contains("Hello"), !body.contains("World") else {
            throw TestFailure("Expected connection check to use a single micro-translation payload, got \(body)")
        }
    }

    private static func assertConnectionCheckAcceptsPlainTextMicroTranslation() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "你好"

        let checker = LLMConnectionChecker(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let isAvailable = await checker.isAvailable()
        guard isAvailable else {
            throw TestFailure("Expected connection check to accept a single plain-text micro-translation")
        }
    }

    private static func assertConnectionCheckAcceptsMalformedTranslationContent() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "Here is the translation: 你好"

        let checker = LLMConnectionChecker(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = await checker.checkAvailability()
        guard result == .available else {
            throw TestFailure("Expected connection check to accept callable model even when content is not strict JSON, got \(result)")
        }
    }

    private static func assertConnectionCheckRejectsHTTPError() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.chatStatusCode = 401

        let checker = LLMConnectionChecker(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = await checker.checkAvailability()
        guard result == .unavailable else {
            throw TestFailure("Expected connection check to reject auth HTTP failures, got \(result)")
        }
    }

    private static func assertConnectionCheckMarksRateLimitTransient() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.chatStatusCode = 429

        let checker = LLMConnectionChecker(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = await checker.checkAvailability()
        guard result == .transientFailure else {
            throw TestFailure("Expected connection check to treat 429 as transient, got \(result)")
        }
    }

    private static func assertSingleBlockPlainTextParses() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "你好"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Hello"], from: "en", to: "zh-Hans")
        guard result == ["你好"] else {
            throw TestFailure("Expected single plain text response to parse, got \(result)")
        }
    }

    private static func assertSingleBlockExplanationParses() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "Here is the translation: 你好"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Hello"], from: "en", to: "zh-Hans")
        guard result == ["你好"] else {
            throw TestFailure("Expected single explanation response to parse, got \(result)")
        }
    }

    private static func assertSingleBlockProtocolNoiseIsFiltered() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "data: {\"type\":\"response.start\"}\n设置\ndata: [DONE]"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(["Settings"], from: "en", to: "zh-Hans")
        guard result == ["设置"] else {
            throw TestFailure("Expected protocol edge noise to be removed, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected protocol cleanup without repair, got \(MockOpenAIProtocol.requestBodies.count) requests")
        }
    }

    private static func assertSingleBlockControlTokensAreFiltered() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "\u{0000}<|assistant|>设置<|end|>\u{0007}"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(["Settings"], from: "en", to: "zh-Hans")
        guard result == ["设置"] else {
            throw TestFailure("Expected model control tokens to be removed, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected control-token cleanup without repair, got \(MockOpenAIProtocol.requestBodies.count) requests")
        }
    }

    private static func assertSingleBlockHTTPHeadersAreFiltered() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "HTTP/1.1 200 OK\nContent-Type: text/event-stream\nX-Request-ID: demo\n\n设置"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(["Settings"], from: "en", to: "zh-Hans")
        guard result == ["设置"] else {
            throw TestFailure("Expected HTTP response headers at the edge to be removed, got \(result)")
        }
    }

    private static func assertUnchangedSingleEnglishWordUsesLocalFallback() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "Settings"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Settings"], from: "en", to: "zh-Hans")
        guard result == ["设置"] else {
            throw TestFailure("Expected unchanged single English word to use local fallback, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected local fallback to avoid a repair request, got \(MockOpenAIProtocol.requestBodies.count) requests")
        }
    }

    private static func assertCommonShortUIWordUsesLocalFallback() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "Pricing"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Pricing"], from: "en", to: "zh-Hans")
        guard result == ["价格"] else {
            throw TestFailure("Expected unchanged common UI word to use local fallback, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected local fallback to avoid a repair request, got \(MockOpenAIProtocol.requestBodies.count) requests")
        }
    }

    private static func assertEchoedRepairPromptDoesNotRenderAsTranslation() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = [
            "target=zh-Hans\noriginal_items:\n0\tSettings\nConvert this model output to JSON string array only:\n设置",
            "设置"
        ]

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Settings"], from: "en", to: "zh-Hans")
        guard result == ["设置"], MockOpenAIProtocol.requestBodies.count == 2 else {
            throw TestFailure("Expected malformed output to recover with one bounded repair request")
        }
    }

    private static func assertLabeledSingleTranslationExtractsChinese() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "原文：Settings\n译文：设置"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Settings"], from: "en", to: "zh-Hans")
        guard result == ["设置"] else {
            throw TestFailure("Expected labeled single translation to extract only Chinese, got \(result)")
        }
    }

    private static func assertAbbreviationUsesSurroundingContext() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"["客户关系管理","客户关系管理系统"]"#

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(
            ["CRM", "Customer relationship management platform"],
            from: "en",
            to: "zh-Hans"
        )
        guard result == ["客户关系管理", "客户关系管理系统"] else {
            throw TestFailure("Expected abbreviation translation to use surrounding OCR context, got \(result)")
        }
        let body = MockOpenAIProtocol.requestBodies.first ?? ""
        guard body.contains("surrounding OCR items as context"),
              body.contains("CRM"),
              body.contains("Customer relationship management platform") else {
            throw TestFailure("Expected one contextual translation request containing the abbreviation and nearby text")
        }
    }

    private static func assertArrowOutputAvoidsRepairRequest() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = [
            "Here are the translations:\nHello => 你好\nWorld => 世界",
            #"["你好","世界"]"#
        ]

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Hello", "World"], from: "en", to: "zh-Hans")
        guard result == ["你好", "世界"] else {
            throw TestFailure("Expected arrow-formatted output to parse locally, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected local arrow parsing without a repair request")
        }
    }

    private static func assertTypicalLargeSelectionStaysSingleRequest() async throws {
        MockOpenAIProtocol.reset()
        let input = (0..<48).map { "Source \($0)" }
        let expected = (0..<48).map { "译文\($0)" }
        MockOpenAIProtocol.assistantContent = String(data: try JSONSerialization.data(withJSONObject: expected), encoding: .utf8)!

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(input, from: "en", to: "zh-Hans")
        guard result == expected, MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected 48 short blocks to translate in one request, requests=\(MockOpenAIProtocol.requestBodies.count)")
        }
    }

    private static func assertPolicyLikeBatchOutputDoesNotSpendRepairRequest() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = [
            #"["被拒绝","是高风险"]"#,
            #"["个性化模型推荐器","探索智能体"]"#
        ]

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        do {
            _ = try await translator.translate(
                ["Personalized model recommender", "Explore agents"],
                from: "en",
                to: "zh-Hans"
            )
            throw TestFailure("Expected suspicious semantic output to fail validation")
        } catch let error as TestFailure {
            throw error
        } catch {
            guard MockOpenAIProtocol.requestBodies.count == 1 else {
                throw TestFailure("Semantic validation must not trigger a format repair request")
            }
        }
    }

    private static func assertRepairFailureDoesNotFanOutRequests() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = [
            "Translations: hello and world",
            "Still not JSON",
            "你好",
            "世界"
        ]

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        do {
            _ = try await translator.translate(["Hello", "World"], from: "en", to: "zh-Hans")
            throw TestFailure("Expected invalid repair output to fail without per-item fan-out")
        } catch let error as TestFailure {
            throw error
        } catch {
            guard MockOpenAIProtocol.requestBodies.count == 2 else {
                throw TestFailure("Expected only one batch request and one bounded repair, got \(MockOpenAIProtocol.requestBodies.count)")
            }
        }
    }

    private static func restore(_ value: Any?, forKey key: String) {
        let defaults = UserDefaults.standard
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}

private final class MockOpenAIProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var hosts: [String] = []
    private static var paths: [String] = []
    private static var authorizations: [String] = []
    private static var bodies: [String] = []
    static var assistantContent = "0\t你好\n1\t世界"
    static var assistantContentQueue: [String] = []
    static var chatStatusCode = 200
    static var modelsStatusCode = 200
    static var statusCodeQueue: [Int] = []

    static var requestedHosts: [String] {
        lock.lock()
        defer { lock.unlock() }
        return hosts
    }

    static var requestedPaths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return paths
    }

    static var authorizationHeaders: [String] {
        lock.lock()
        defer { lock.unlock() }
        return authorizations
    }

    static var requestBodies: [String] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    static func reset() {
        lock.lock()
        hosts = []
        paths = []
        authorizations = []
        bodies = []
        assistantContent = "0\t你好\n1\t世界"
        assistantContentQueue = []
        chatStatusCode = 200
        modelsStatusCode = 200
        statusCodeQueue = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "shotlens-test.local" || request.url?.host == "api.siliconflow.cn"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let content: String
        Self.lock.lock()
        if Self.assistantContentQueue.isEmpty {
            content = Self.assistantContent
        } else {
            content = Self.assistantContentQueue.removeFirst()
        }
        Self.hosts.append(request.url?.host ?? "")
        Self.paths.append(path)
        Self.authorizations.append(request.value(forHTTPHeaderField: "Authorization") ?? "")
        Self.bodies.append(Self.bodyString(from: request))
        Self.lock.unlock()

        let statusCode: Int
        if !Self.statusCodeQueue.isEmpty {
            statusCode = Self.statusCodeQueue.removeFirst()
        } else if path == "/v1/chat/completions" {
            statusCode = Self.chatStatusCode
        } else if path == "/v1/models" {
            statusCode = Self.modelsStatusCode
        } else {
            statusCode = 404
        }
        let body: String = statusCode == 200
            ? try! String(data: JSONSerialization.data(withJSONObject: [
                "choices": [
                    [
                        "message": [
                            "content": content
                        ]
                    ]
                ]
            ]), encoding: .utf8)!
            : #"{"error":{"message":"not found"}}"#

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func bodyString(from request: URLRequest) -> String {
        if let httpBody = request.httpBody {
            return String(data: httpBody, encoding: .utf8) ?? ""
        }

        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }

        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read > 0 {
                data.append(buffer, count: read)
            } else {
                break
            }
        }
        return String(data: data, encoding: .utf8) ?? ""
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
