import Foundation

struct LLMTranslator: TranslationProvider {
    let name = "大模型翻译"
    let settings: TranslationSettings

    func translate(_ texts: [String], from sourceLanguage: String, to targetLanguage: String) async throws -> [String] {
        guard settings.isLLMConfigured else {
            throw TranslationError.llmNotConfigured
        }

        guard let url = settings.chatCompletionsURL else {
            throw TranslationError.invalidLLMEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(settings.effectiveAPIKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 45

        var payload: [String: Any] = [
            "temperature": 0,
            "messages": [
                [
                    "role": "system",
                    "content": "Translate numbered OCR blocks to \(targetLanguage). Use literal translation. Do not polish. Do not rewrite. Return only numbered TSV lines: index<TAB>translation. Keep the same indexes and count. Translate every block completely. Do not omit, truncate, merge, summarize, or explain."
                ],
                [
                    "role": "user",
                    "content": try makeUserPayload(texts: texts, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
                ]
            ]
        ]
        if !settings.effectiveModel.isEmpty {
            payload["model"] = settings.effectiveModel
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw TranslationError.llmHTTPError(statusCode: http.statusCode, body: body)
        }

        let content = try parseAssistantContent(from: data)
        let translated = try parseTranslations(from: content, expectedCount: texts.count)
        guard translated.count == texts.count else {
            throw TranslationError.llmResponseCountMismatch(expected: texts.count, actual: translated.count)
        }
        return translated
    }

    private func makeUserPayload(texts: [String], sourceLanguage: String, targetLanguage: String) throws -> String {
        var lines = [
            "source=\(sourceLanguage)",
            "target=\(targetLanguage)",
            "format=index<TAB>text"
        ]
        for (index, text) in texts.enumerated() {
            lines.append("\(index)\t\(text.lineProtocolEscaped)")
        }
        return lines.joined(separator: "\n")
    }

    private func parseAssistantContent(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw TranslationError.invalidLLMResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseTranslations(from content: String, expectedCount: Int) throws -> [String] {
        if let lines = parseNumberedLines(from: content, expectedCount: expectedCount) {
            return lines
        }
        return try parseStringArray(from: content)
    }

    private func parseNumberedLines(from content: String, expectedCount: Int) -> [String]? {
        let normalized = content
            .replacingOccurrences(of: "```tsv", with: "")
            .replacingOccurrences(of: "```text", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var parsedLines: [(index: Int, text: String)] = []
        for rawLine in normalized.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if let parsed = parseNumberedTranslationLine(line) {
                parsedLines.append(parsed)
            }
        }

        guard parsedLines.count == expectedCount else {
            return nil
        }

        let rawIndexes = parsedLines.map(\.index)
        let usesZeroBasedIndexes = rawIndexes.allSatisfy { (0..<expectedCount).contains($0) }
        let usesOneBasedIndexes = rawIndexes.allSatisfy { (1...expectedCount).contains($0) }
        guard usesZeroBasedIndexes || usesOneBasedIndexes else { return nil }

        var values = Array(repeating: "", count: expectedCount)
        var seenIndexes = Set<Int>()
        for parsed in parsedLines {
            let normalizedIndex = usesZeroBasedIndexes ? parsed.index : parsed.index - 1
            guard !seenIndexes.contains(normalizedIndex) else { return nil }
            values[normalizedIndex] = parsed.text
            seenIndexes.insert(normalizedIndex)
        }

        guard values.allSatisfy({ !$0.isEmpty }) else { return nil }
        return values
    }

    private func parseNumberedTranslationLine(_ line: String) -> (index: Int, text: String)? {
        let pattern = #"^\s*(\d+)\s*(?:\t|[.)、:：-])\s*(.+?)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsLine = line as NSString
        let match = regex.firstMatch(
            in: line,
            range: NSRange(location: 0, length: nsLine.length)
        )
        guard let match,
              match.numberOfRanges == 3,
              let index = Int(nsLine.substring(with: match.range(at: 1))) else {
            return nil
        }

        let text = nsLine.substring(with: match.range(at: 2))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return (index, text)
    }

    private func parseStringArray(from content: String) throws -> [String] {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String

        if trimmed.hasPrefix("```") {
            let lines = trimmed.components(separatedBy: .newlines)
            jsonText = lines
                .dropFirst()
                .dropLast(lines.last?.hasPrefix("```") == true ? 1 : 0)
                .joined(separator: "\n")
        } else if let start = trimmed.firstIndex(of: "["),
                  let end = trimmed.lastIndex(of: "]") {
            jsonText = String(trimmed[start...end])
        } else {
            jsonText = trimmed
        }

        guard let data = jsonText.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [String] else {
            throw TranslationError.invalidLLMResponse
        }
        return values
    }
}

private extension String {
    var lineProtocolEscaped: String {
        replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
