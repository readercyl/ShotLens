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
        try await assertXiaomiMiMoUsesDirectStructuredTranslation()
        try await assertDeepSeekUsesNonThinkingPlainTranslation()
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
            assistantContent: #"{"target_language":"zh-Hans","texts":["独立分析人工智能技术；」「了解人工智能领域的现状。"],"source_language":"en"}"#,
            input: ["Independent analysis of AI technology", "Understand the state of the AI field"],
            expected: ["独立分析人工智能技术；", "了解人工智能领域的现状。"]
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
        try await assertShortEnglishWordEchoIsRetried()
        try await assertCommonShortUIWordUsesLocalFallback()
        try await assertMixedLocalAndRemoteTranslationsAreReassembled()
        try await assertExactBatchUsesSessionCache()
        try await assertMalformedOutputFailsAfterBoundedRetry()
        try await assertLabeledSingleTranslationExtractsChinese()
        try await assertAbbreviationUsesSurroundingContext()
        try await assertArrowOutputAvoidsRepairRequest()
        try await assertLargeSelectionUsesBoundedBatches()
        try await assertMalformedLargeBatchUsesOneBoundedRecovery()
        try await assertLongSemanticBlockSplitsAndReassembles()
        try await assertIndexedJSONStringsAreAlignedWithoutRepair()
        try await assertMissingIndexedItemRecoversWithSingleItemRetry()
        try await assertPartialIndexedObjectKeepsAvailableItems()
        try await assertSingleMiddleIndexedObjectKeepsItsPosition()
        try await assertNestedMetadataDoesNotDiscardTranslations()
        try await assertNestedArrayDoesNotDiscardTranslations()
        try await assertIncompleteJSONObjectKeepsIndexedTranslations()
        try await assertExistingChineseMustBePreserved()
        try await assertExistingNumbersMustBePreserved()
        try await assertProductIdentifierMayRemainUntranslated()
        try await assertPunctuatedIndexedJSONStaysSingleRequest()
        try await assertUntranslatedSentenceFailsAfterBoundedRetry()
        try await assertCustomSavedSettingsSurviveLoad()
        try await assertEmptySavedSettingsStayUnconfigured()
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

    private static func assertXiaomiMiMoUsesDirectStructuredTranslation() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"{"translations":["账户已准备就绪","选择匹配工作流程的模型"]}"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://api.xiaomimimo.com/v1",
            apiKey: "mimo-test-key",
            model: "mimo-v2.5"
        ))

        let result = try await translator.translate(
            ["Your account is ready", "Choose a model matching your workflow"],
            from: "en",
            to: "zh-Hans"
        )
        guard result == ["账户已准备就绪", "选择匹配工作流程的模型"] else {
            throw TestFailure("Unexpected MiMo translations: \(result)")
        }
        let body = MockOpenAIProtocol.requestBodies.first ?? ""
        guard body.contains(#""thinking":{"type":"disabled"}"#),
              body.contains("max_completion_tokens"),
              !body.contains("response_format") else {
            throw TestFailure("Expected MiMo request to disable thinking and use numbered text: \(body)")
        }
        guard MockOpenAIProtocol.apiKeyHeaders == ["mimo-test-key"] else {
            throw TestFailure("Expected official MiMo api-key header")
        }
    }

    private static func assertDeepSeekUsesNonThinkingPlainTranslation() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "0\t你好\n1\t世界"
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://api.deepseek.com",
            apiKey: "deepseek-test-key",
            model: "deepseek-v4-flash"
        ))

        let result = try await translator.translate(["Hello", "World"], from: "en", to: "zh-Hans")
        guard result == ["你好", "世界"] else {
            throw TestFailure("Unexpected DeepSeek translations: \(result)")
        }
        let body = MockOpenAIProtocol.requestBodies.first ?? ""
        guard body.contains(#""thinking":{"type":"disabled"}"#),
              body.contains("max_tokens"),
              body.contains(#"0\tHello"#),
              !body.contains("response_format") else {
            throw TestFailure("Expected DeepSeek non-thinking numbered request: \(body)")
        }
    }

    private static func assertCustomSavedSettingsSurviveLoad() async throws {
        let defaults = UserDefaults.standard
        let originalEndpoint = defaults.object(forKey: TranslationSettings.apiEndpointKey)
        let originalKey = defaults.object(forKey: TranslationSettings.apiKeyKey)
        let originalModel = defaults.object(forKey: TranslationSettings.modelKey)
        defer {
            restore(originalEndpoint, forKey: TranslationSettings.apiEndpointKey)
            restore(originalKey, forKey: TranslationSettings.apiKeyKey)
            restore(originalModel, forKey: TranslationSettings.modelKey)
        }

        TranslationSettings(
            apiEndpoint: "https://custom.example/v1",
            apiKey: "custom-key",
            model: "custom-model"
        ).save()

        let loaded = TranslationSettings.load()
        guard loaded.apiEndpoint == "https://custom.example/v1",
              loaded.apiKey == "custom-key",
              loaded.model == "custom-model",
              loaded.effectiveAPIEndpoint == "https://custom.example/v1",
              loaded.effectiveAPIKey == "custom-key",
              loaded.effectiveModel == "custom-model" else {
            throw TestFailure("Expected custom API settings to survive load, got \(loaded)")
        }
    }

    private static func assertEmptySavedSettingsStayUnconfigured() async throws {
        let defaults = UserDefaults.standard
        let originalEndpoint = defaults.object(forKey: TranslationSettings.apiEndpointKey)
        let originalKey = defaults.object(forKey: TranslationSettings.apiKeyKey)
        let originalModel = defaults.object(forKey: TranslationSettings.modelKey)
        defer {
            restore(originalEndpoint, forKey: TranslationSettings.apiEndpointKey)
            restore(originalKey, forKey: TranslationSettings.apiKeyKey)
            restore(originalModel, forKey: TranslationSettings.modelKey)
        }

        TranslationSettings.resetSavedConfiguration()
        let settings = TranslationSettings.load()
        guard settings.apiEndpoint.isEmpty,
              settings.apiKey.isEmpty,
              settings.model.isEmpty,
              !settings.isLLMConfigured else {
            throw TestFailure("Expected empty saved settings to remain unconfigured, got \(settings)")
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
        let result = try await translator.translate(["Account preferences"], from: "en", to: "zh-Hans")
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
        let result = try await translator.translate(["Account preferences"], from: "en", to: "zh-Hans")
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
        let result = try await translator.translate(["Account preferences"], from: "en", to: "zh-Hans")
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
        guard MockOpenAIProtocol.requestBodies.isEmpty else {
            throw TestFailure("Expected deterministic UI translation to skip the network")
        }
    }

    private static func assertShortEnglishWordEchoIsRetried() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = ["abstract", "摘要"]

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["abstract"], from: "en", to: "zh-Hans")
        guard result == ["摘要"],
              MockOpenAIProtocol.requestBodies.count == 2,
              MockOpenAIProtocol.requestBodies[0].contains("one isolated OCR word"),
              MockOpenAIProtocol.requestBodies[1].contains("recovery attempt"),
              MockOpenAIProtocol.requestTimeouts == [15, 10] else {
            throw TestFailure("Expected an echoed isolated word to use a distinct fast recovery retry, got \(result), requests=\(MockOpenAIProtocol.requestBodies.count), timeouts=\(MockOpenAIProtocol.requestTimeouts)")
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

        let result = try await translator.translate(["Pricing", "Updated", "Release"], from: "en", to: "zh-Hans")
        guard result == ["价格", "已更新", "发布"] else {
            throw TestFailure("Expected common UI words to use local fallbacks, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.isEmpty else {
            throw TestFailure("Expected deterministic UI translation to skip the network")
        }
    }

    private static func assertMixedLocalAndRemoteTranslationsAreReassembled() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"{"translations":["解释缓存策略"]}"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(
            ["Settings", "Explain the cache policy", "Cancel"],
            from: "en",
            to: "zh-Hans"
        )
        guard result == ["设置", "解释缓存策略", "取消"] else {
            throw TestFailure("Expected local and remote translations to be reassembled in place, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1,
              let body = MockOpenAIProtocol.requestBodies.first,
              body.contains("Explain the cache policy"),
              !body.contains("Settings"),
              !body.contains("Cancel") else {
            throw TestFailure("Expected only unknown text to reach the translation API")
        }
    }

    private static func assertExactBatchUsesSessionCache() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"{"translations":["唯一缓存探针句子 7319"]}"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "cache-test-model"
        ))
        let input = ["Unique cache probe sentence 7319"]

        let first = try await translator.translate(input, from: "en", to: "zh-Hans")
        let second = try await translator.translate(input, from: "en", to: "zh-Hans")
        guard first == ["唯一缓存探针句子 7319"], second == first else {
            throw TestFailure("Expected an exact cached translation result")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected the identical second batch to skip the network")
        }
    }

    private static func assertMalformedOutputFailsAfterBoundedRetry() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "target=zh-Hans\noriginal_items:\n0\tAccount preferences\ninvalid output"

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        do {
            _ = try await translator.translate(["Account preferences"], from: "en", to: "zh-Hans")
            throw TestFailure("Expected malformed output to fail")
        } catch is TestFailure {
            throw TestFailure("Expected malformed output to fail")
        } catch {
            guard MockOpenAIProtocol.requestBodies.count == 2 else {
                throw TestFailure("Malformed output should receive one bounded item retry")
            }
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

        let result = try await translator.translate(["Application preferences"], from: "en", to: "zh-Hans")
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
        guard body.contains("Use the whole batch as context"),
              body.contains("CRM"),
              body.contains("Customer relationship management platform"),
              body.contains(#"0\tCRM"#),
              !body.contains(#"\"items\""#) else {
            throw TestFailure("Expected one contextual numbered-text request containing the abbreviation and nearby text")
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

    private static func assertLargeSelectionUsesBoundedBatches() async throws {
        MockOpenAIProtocol.reset()
        let input = (0..<48).map { index in
            String(repeating: "Source text for bounded batch ", count: 4) + "\(index)"
        }
        let expected = (0..<48).map { "译文\($0)" }
        let firstBatch = Array(expected[0..<24])
        let secondBatch = Array(expected[24..<48])
        MockOpenAIProtocol.assistantContentQueue = [
            String(data: try JSONSerialization.data(withJSONObject: firstBatch), encoding: .utf8)!,
            String(data: try JSONSerialization.data(withJSONObject: secondBatch), encoding: .utf8)!
        ]

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(input, from: "en", to: "zh-Hans")
        guard result == expected, MockOpenAIProtocol.requestBodies.count == 2 else {
            throw TestFailure("Expected a large selection to use two bounded requests, requests=\(MockOpenAIProtocol.requestBodies.count)")
        }
    }

    private static func assertMalformedLargeBatchUsesOneBoundedRecovery() async throws {
        MockOpenAIProtocol.reset()
        let input = (0..<24).map { "Source item \($0)" }
        let expected = (0..<24).map { "译文\($0)" }
        MockOpenAIProtocol.assistantContentQueue = [
            "invalid output",
            String(data: try JSONSerialization.data(withJSONObject: expected), encoding: .utf8)!
        ]

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(input, from: "en", to: "zh-Hans")
        guard result == expected, MockOpenAIProtocol.requestBodies.count == 2 else {
            throw TestFailure("Expected a malformed large batch to recover as one bounded batch, requests=\(MockOpenAIProtocol.requestBodies.count)")
        }
    }

    private static func assertLongSemanticBlockSplitsAndReassembles() async throws {
        MockOpenAIProtocol.reset()
        let source = String(repeating: "This is a long sentence that should be split safely. ", count: 110)
        MockOpenAIProtocol.assistantContentQueue = [#"["第一段"]"#, #"["第二段"]"#]
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate([source], from: "en", to: "zh-Hans")
        guard result == ["第一段第二段"],
              MockOpenAIProtocol.requestBodies.count == 2 else {
            throw TestFailure("Expected a long semantic block to split and reassemble")
        }
        let bodies = MockOpenAIProtocol.requestBodies.joined(separator: "\n")
        guard bodies.contains(#"0\tThis is"#), bodies.contains(#"0\t"#) else {
            throw TestFailure("Expected the long semantic block to be sent as bounded numbered segments")
        }
    }

    private static func assertIndexedJSONStringsAreAlignedWithoutRepair() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"["0 产品版本更新","1 Intelligence Index v4.1","2 功能更新"]"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(
            ["Product release update", "Intelligence Index v4.1", "features updates"],
            from: "en",
            to: "zh-Hans"
        )
        guard result == ["产品版本更新", "Intelligence Index v4.1", "功能更新"] else {
            throw TestFailure("Expected indexed JSON strings to align locally, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 1,
              MockOpenAIProtocol.requestBodies[0].contains(#"0\tProduct release update"#) else {
            throw TestFailure("Expected a single numbered-text input request")
        }
    }

    private static func assertMissingIndexedItemRecoversWithSingleItemRetry() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = [
            #"["0 个性化模型推荐器","2 探索高级计划"]"#,
            #"["探索适用于一般工作、编程和客户支持的智能助手"]"#
        ]
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(
                ["Personalized model recommender", "Explore agents for general work, coding, and customer support", "Explore premium plans"],
                from: "en",
                to: "zh-Hans"
            )
        guard result == ["个性化模型推荐器", "探索适用于一般工作、编程和客户支持的智能助手", "探索高级计划"],
              MockOpenAIProtocol.requestBodies.count == 2 else {
            throw TestFailure("Expected missing indexed item to recover with one item retry: \(result), requests=\(MockOpenAIProtocol.requestBodies.count)")
        }
    }

    private static func assertPartialIndexedObjectKeepsAvailableItems() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = [
            #"{"0":"版本更新","2":"功能说明"}"#,
            "0\t页面标题"
        ]
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translateAvailable(
            ["Release update", "Page title", "Feature description"],
            from: "en",
            to: "zh-Hans"
        )
        guard result.translations[0] == "版本更新",
              result.translations[1] == "页面标题",
              result.translations[2] == "功能说明",
              result.completedCount == 3,
              result.isComplete else {
            throw TestFailure("Expected valid indexed items to survive and recover a partial response: \(result.translations)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 2 else {
            throw TestFailure("Partial response should receive one bounded retry")
        }
    }

    private static func assertSingleMiddleIndexedObjectKeepsItsPosition() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = [
            #"{"1":"页面标题"}"#,
            "0\t更新\n1\t说明"
        ]
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translateAvailable(
            ["Release update", "Page title", "Feature description"],
            from: "en",
            to: "zh-Hans"
        )
        guard result.translations[0] == "更新",
              result.translations[1] == "页面标题",
              result.translations[2] == "说明",
              result.completedCount == 3 else {
            throw TestFailure("Expected the middle item to keep its position after retries: \(result.translations)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 2 else {
            throw TestFailure("Missing items should share one bounded recovery request")
        }
    }

    private static func assertNestedMetadataDoesNotDiscardTranslations() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"{"source_language":"en","items":{"3":"适用场景","0":"独立分析","2":"选择模型","1":"人工智能分析","target_language":"zh-Hans"}}"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(
            ["Independent analysis", "AI analysis", "Choose a model", "Use cases"],
            from: "en",
            to: "zh-Hans"
        )
        guard result == ["独立分析", "人工智能分析", "选择模型", "适用场景"] else {
            throw TestFailure("Nested metadata discarded valid translations: \(result)")
        }
    }

    private static func assertNestedArrayDoesNotDiscardTranslations() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"{"items":[{"1":"速度","0":"亮点","2":"每项任务的成本"},{"source_language":"en","target_language":"zh-Hans"}]}"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(
            ["Highlights", "Speed", "Cost per Task"],
            from: "en",
            to: "zh-Hans"
        )
        guard result == ["亮点", "速度", "每项任务的成本"] else {
            throw TestFailure("Nested array discarded valid translations: \(result)")
        }
    }

    private static func assertIncompleteJSONObjectKeepsIndexedTranslations() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"{"items":{"0":"模型推荐","1":"平台支持""#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(
            ["Model recommendation", "Platform support"],
            from: "en",
            to: "zh-Hans"
        )
        guard result == ["模型推荐", "平台支持"] else {
            throw TestFailure("Incomplete JSON lost recoverable translations: \(result)")
        }
    }

    private static func assertExistingChineseMustBePreserved() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "0\t删除原有中文后的英语"
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        do {
            _ = try await translator.translate(["保留中文 English"], from: "en", to: "zh-Hans")
            throw TestFailure("Expected altered Chinese source text to be rejected")
        } catch is TestFailure {
            throw TestFailure("Expected altered Chinese source text to be rejected")
        } catch {
            guard MockOpenAIProtocol.requestBodies.count == 2 else {
                throw TestFailure("Chinese-preservation failure should receive one bounded retry")
            }
        }
    }

    private static func assertExistingNumbersMustBePreserved() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = "0\t节省费用并立即开始"
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        do {
            _ = try await translator.translate(["Save 30% and start with $15"], from: "en", to: "zh-Hans")
            throw TestFailure("Expected altered numeric source text to be rejected")
        } catch is TestFailure {
            throw TestFailure("Expected altered numeric source text to be rejected")
        } catch {
            guard MockOpenAIProtocol.requestBodies.count == 2 else {
                throw TestFailure("Number-preservation failure should receive one bounded retry")
            }
        }
    }

    private static func assertUntranslatedSentenceFailsAfterBoundedRetry() async throws {
        MockOpenAIProtocol.reset()
        let source = "Compare AI agents across capabilities, pricing, and platform support"
        MockOpenAIProtocol.assistantContent = String(
            data: try JSONSerialization.data(withJSONObject: [source]),
            encoding: .utf8
        )!
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        do {
            _ = try await translator.translate([source], from: "en", to: "zh-Hans")
            throw TestFailure("Expected untranslated sentence to fail")
        } catch is TestFailure {
            throw TestFailure("Expected untranslated sentence to fail")
        } catch {
            guard MockOpenAIProtocol.requestBodies.count == 2 else {
                throw TestFailure("Untranslated output should receive one bounded retry")
            }
        }
    }

    private static func assertProductIdentifierMayRemainUntranslated() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"["AA-Briefcase"]"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(["AA-Briefcase"], from: "en", to: "zh-Hans")
        guard result == ["AA-Briefcase"], MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected product identifier to remain unchanged without failing the batch")
        }
    }

    private static func assertPunctuatedIndexedJSONStaysSingleRequest() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = #"["0. 版本更新","1: 页面标题","2、功能说明"]"#
        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))
        let result = try await translator.translate(["Release update", "Page title", "Feature description"], from: "en", to: "zh-Hans")
        guard result == ["版本更新", "页面标题", "功能说明"], MockOpenAIProtocol.requestBodies.count == 1 else {
            throw TestFailure("Expected punctuated indexes to be stripped and aligned locally, got \(result)")
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
    private static var apiKeys: [String] = []
    private static var bodies: [String] = []
    private static var timeouts: [TimeInterval] = []
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

    static var apiKeyHeaders: [String] {
        lock.lock()
        defer { lock.unlock() }
        return apiKeys
    }

    static var requestBodies: [String] {
        lock.lock()
        defer { lock.unlock() }
        return bodies
    }

    static var requestTimeouts: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return timeouts
    }

    static func reset() {
        LLMTranslator.resetSessionCacheForTesting()
        lock.lock()
        hosts = []
        paths = []
        authorizations = []
        apiKeys = []
        bodies = []
        timeouts = []
        assistantContent = "0\t你好\n1\t世界"
        assistantContentQueue = []
        chatStatusCode = 200
        modelsStatusCode = 200
        statusCodeQueue = []
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "shotlens-test.local"
            || request.url?.host == "api.xiaomimimo.com"
            || request.url?.host == "api.deepseek.com"
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
        Self.apiKeys.append(request.value(forHTTPHeaderField: "api-key") ?? "")
        Self.bodies.append(Self.bodyString(from: request))
        Self.timeouts.append(request.timeoutInterval)
        Self.lock.unlock()

        let statusCode: Int
        if !Self.statusCodeQueue.isEmpty {
            statusCode = Self.statusCodeQueue.removeFirst()
        } else if path == "/v1/chat/completions" || path == "/chat/completions" {
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
