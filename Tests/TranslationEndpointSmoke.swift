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
            assistantContent: "你好\n世界"
        )
        try await assertSingleBlockPlainTextParses()
        try await assertRepairRequestFixesInvalidBatchResponse()
        try await assertSingleItemFallbackRecoversWhenRepairFails()
        try await assertEmptySavedSettingsUseDefaultAPI()
        try await assertConnectionCheckUsesChatCompletions()
        try await assertConnectionCheckRejectsInvalidTranslationFormat()

        print("Translation endpoint smoke test passed.")
    }

    private static func assertTranslates(
        endpoint: String,
        expectedPath: String,
        assistantContent: String = "0\t你好\n1\t世界"
    ) async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContent = assistantContent

        let translator = LLMTranslator(settings: TranslationSettings(
            apiEndpoint: endpoint,
            apiKey: "test-key",
            model: "test-model"
        ))

        let result = try await translator.translate(["Hello", "World"], from: "en", to: "zh-Hans")
        guard result == ["你好", "世界"] else {
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
        defer {
            restore(originalEndpoint, forKey: TranslationSettings.apiEndpointKey)
            restore(originalKey, forKey: TranslationSettings.apiKeyKey)
            restore(originalModel, forKey: TranslationSettings.modelKey)
        }

        defaults.removeObject(forKey: TranslationSettings.apiEndpointKey)
        defaults.removeObject(forKey: TranslationSettings.apiKeyKey)
        defaults.removeObject(forKey: TranslationSettings.modelKey)

        let settings = TranslationSettings.load()
        guard settings.apiEndpoint == TranslationSettings.defaultAPIEndpoint else {
            throw TestFailure("Expected default endpoint to load when none is saved")
        }
        guard settings.apiKey.isEmpty, settings.usesDefaultAPIKey else {
            throw TestFailure("Expected saved API key to stay hidden while using default fallback")
        }
        guard settings.model == TranslationSettings.defaultModel else {
            throw TestFailure("Expected default model to load when none is saved")
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

    private static func assertConnectionCheckUsesChatCompletions() async throws {
        MockOpenAIProtocol.reset()
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
    }

    private static func assertConnectionCheckRejectsInvalidTranslationFormat() async throws {
        MockOpenAIProtocol.reset()
        MockOpenAIProtocol.assistantContentQueue = ["Here is the answer: OK", "Still invalid"]

        let checker = LLMConnectionChecker(settings: TranslationSettings(
            apiEndpoint: "https://shotlens-test.local/v1",
            apiKey: "test-key",
            model: "test-model"
        ))

        let isAvailable = await checker.isAvailable()
        guard !isAvailable else {
            throw TestFailure("Expected connection check to reject unparseable translation content")
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

    private static func assertRepairRequestFixesInvalidBatchResponse() async throws {
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
            throw TestFailure("Expected repair request to recover JSON array, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 2,
              MockOpenAIProtocol.requestBodies[1].contains("Convert this model output") else {
            throw TestFailure("Expected second request to be a format repair request")
        }
    }

    private static func assertSingleItemFallbackRecoversWhenRepairFails() async throws {
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

        let result = try await translator.translate(["Hello", "World"], from: "en", to: "zh-Hans")
        guard result == ["你好", "世界"] else {
            throw TestFailure("Expected per-item fallback to recover translations, got \(result)")
        }
        guard MockOpenAIProtocol.requestBodies.count == 4 else {
            throw TestFailure("Expected batch, repair, and two single-item requests, got \(MockOpenAIProtocol.requestBodies.count)")
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
        if path == "/v1/chat/completions" {
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
