import Foundation

struct LLMConnectionChecker {
    let settings: TranslationSettings

    func isAvailable() async -> Bool {
        guard settings.isLLMConfigured,
              let url = settings.chatCompletionsURL else {
            return false
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12

        var payload: [String: Any] = [
            "temperature": 0,
            "max_tokens": 4,
            "messages": [
                [
                    "role": "user",
                    "content": "Reply OK."
                ]
            ]
        ]
        if !settings.effectiveModel.isEmpty {
            payload["model"] = settings.effectiveModel
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }
}
