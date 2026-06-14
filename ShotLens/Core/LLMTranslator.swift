import Foundation

struct LLMTranslator: TranslationProvider {
    let name = "大模型翻译"
    let settings: TranslationSettings
    private let maxBatchItemCount = 20
    private let maxBatchCharacterCount = 6000

    func translate(_ texts: [String], from sourceLanguage: String, to targetLanguage: String) async throws -> [String] {
        guard !texts.isEmpty else { return [] }

        var translated: [String] = []
        translated.reserveCapacity(texts.count)
        for batch in makeBatches(from: texts) {
            translated.append(contentsOf: try await translateBatch(
                batch,
                from: sourceLanguage,
                to: targetLanguage,
                allowsSingleItemFallback: true
            ))
        }
        return translated
    }

    func validateMicroTranslation(from sourceLanguage: String, to targetLanguage: String) async throws {
        _ = try await translateBatch(
            ["Hello"],
            from: sourceLanguage,
            to: targetLanguage,
            allowsSingleItemFallback: true
        )
    }

    func validateConnectivity(from sourceLanguage: String, to targetLanguage: String) async throws {
        let content = try await requestAssistantContent(
            systemPrompt: "Reply with only a short \(targetLanguage) translation. No Markdown.",
            userPayload: try makeUserPayload(texts: ["Hello"], sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        )
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TranslationError.invalidLLMResponse
        }
    }

    private func translateBatch(
        _ texts: [String],
        from sourceLanguage: String,
        to targetLanguage: String,
        allowsSingleItemFallback: Bool
    ) async throws -> [String] {
        guard settings.isLLMConfigured else {
            throw TranslationError.llmNotConfigured
        }

        let content = try await requestAssistantContent(
            systemPrompt: primarySystemPrompt(targetLanguage: targetLanguage),
            userPayload: try makeUserPayload(texts: texts, sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
        )

        do {
            return try parseTranslations(from: content, expectedCount: texts.count)
        } catch {
            ShotLensLogger.log("批量翻译返回格式异常，尝试修复：\(content.logSnippet)")
            let repairedContent: String
            do {
                repairedContent = try await requestAssistantContent(
                    systemPrompt: repairSystemPrompt(expectedCount: texts.count),
                    userPayload: makeRepairPayload(
                        content: content,
                        expectedCount: texts.count,
                        targetLanguage: targetLanguage
                    )
                )
            } catch {
                guard allowsSingleItemFallback else {
                    throw error
                }
                ShotLensLogger.log("翻译格式修复请求失败，进入逐条兜底", error: error)
                return try await translateItemsIndividually(
                    texts,
                    from: sourceLanguage,
                    to: targetLanguage
                )
            }

            do {
                return try parseTranslations(from: repairedContent, expectedCount: texts.count)
            } catch {
                ShotLensLogger.log("翻译格式修复失败，进入逐条兜底：\(repairedContent.logSnippet)")
                guard allowsSingleItemFallback else {
                    throw error
                }
                return try await translateItemsIndividually(
                    texts,
                    from: sourceLanguage,
                    to: targetLanguage
                )
            }
        }
    }

    private func requestAssistantContent(systemPrompt: String, userPayload: String) async throws -> String {
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
                    "content": systemPrompt
                ],
                [
                    "role": "user",
                    "content": userPayload
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

        return try parseAssistantContent(from: data)
    }

    private func primarySystemPrompt(targetLanguage: String) -> String {
        "Translate OCR text blocks to \(targetLanguage). Return only a valid JSON string array with exactly one string per input block, in the same order. If a block cannot be translated, return the original text for that item. Do not return Markdown, numbering, explanations, objects, or extra text."
    }

    private func repairSystemPrompt(expectedCount: Int) -> String {
        "Convert this model output into only a valid JSON string array with exactly \(expectedCount) strings. Do not translate again. Do not add explanations, Markdown, keys, or numbering."
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

    private func makeRepairPayload(content: String, expectedCount: Int, targetLanguage: String) -> String {
        [
            "target=\(targetLanguage)",
            "expected_count=\(expectedCount)",
            "Convert this model output to JSON string array only:",
            content
        ].joined(separator: "\n")
    }

    private func translateItemsIndividually(_ texts: [String], from sourceLanguage: String, to targetLanguage: String) async throws -> [String] {
        var translated: [String] = []
        translated.reserveCapacity(texts.count)
        for text in texts {
            let content = try await requestAssistantContent(
                systemPrompt: primarySystemPrompt(targetLanguage: targetLanguage),
                userPayload: try makeUserPayload(texts: [text], sourceLanguage: sourceLanguage, targetLanguage: targetLanguage)
            )
            do {
                translated.append(try parseTranslations(from: content, expectedCount: 1)[0])
            } catch {
                let repairedContent: String
                do {
                    repairedContent = try await requestAssistantContent(
                        systemPrompt: repairSystemPrompt(expectedCount: 1),
                        userPayload: makeRepairPayload(
                            content: content,
                            expectedCount: 1,
                            targetLanguage: targetLanguage
                        )
                    )
                } catch {
                    if let bestEffort = bestEffortSingleTranslation(from: content) {
                        translated.append(bestEffort)
                        continue
                    }
                    throw error
                }
                do {
                    translated.append(try parseTranslations(from: repairedContent, expectedCount: 1)[0])
                } catch {
                    if let bestEffort = bestEffortSingleTranslation(from: content) {
                        translated.append(bestEffort)
                    } else {
                        throw error
                    }
                }
            }
        }
        return translated
    }

    private func parseAssistantContent(from data: Data) throws -> String {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = firstNonEmptyString(in: message, keys: ["content", "reasoning_content"]) else {
            throw TranslationError.invalidLLMResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseTranslations(from content: String, expectedCount: Int) throws -> [String] {
        guard expectedCount > 0 else { return [] }

        if let values = parseStructuredJSONIfPresent(from: content), values.count == expectedCount {
            return values
        }
        if let lines = parseNumberedLines(from: content, expectedCount: expectedCount) {
            return lines
        }
        if let lines = parseUnnumberedLines(from: content, expectedCount: expectedCount) {
            return lines
        }
        if expectedCount == 1, let plainText = parseSinglePlainText(from: content) {
            return [plainText]
        }
        throw TranslationError.invalidLLMResponse
    }

    private func makeBatches(from texts: [String]) -> [[String]] {
        var batches: [[String]] = []
        var current: [String] = []
        var currentCharacters = 0

        for text in texts {
            let count = text.count
            let wouldExceedCount = current.count >= maxBatchItemCount
            let wouldExceedCharacters = !current.isEmpty && currentCharacters + count > maxBatchCharacterCount
            if wouldExceedCount || wouldExceedCharacters {
                batches.append(current)
                current = []
                currentCharacters = 0
            }
            current.append(text)
            currentCharacters += count
        }

        if !current.isEmpty {
            batches.append(current)
        }
        return batches
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

    private func parseStructuredJSONIfPresent(from content: String) -> [String]? {
        let trimmed = content.strippingCodeFence.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String

        if let start = trimmed.firstIndex(of: "["),
                  let end = trimmed.lastIndex(of: "]") {
            jsonText = String(trimmed[start...end])
        } else if let start = trimmed.firstIndex(of: "{"),
                  let end = trimmed.lastIndex(of: "}") {
            jsonText = String(trimmed[start...end])
        } else {
            jsonText = trimmed
        }

        guard let data = jsonText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return translations(fromJSONObject: object)
    }

    private func translations(fromJSONObject object: Any) -> [String]? {
        if let values = object as? [String] {
            return values.map(\.cleanedTranslationText).filter { !$0.isEmpty }
        }

        if let array = object as? [Any] {
            let values = array.compactMap { item -> String? in
                if let value = item as? String {
                    return value.cleanedTranslationText
                }
                if let dictionary = item as? [String: Any] {
                    return firstNonEmptyString(in: dictionary, keys: ["translation", "translated", "translatedText", "text", "value"])?.cleanedTranslationText
                }
                return nil
            }
            return values.count == array.count ? values.filter { !$0.isEmpty } : nil
        }

        guard let dictionary = object as? [String: Any] else { return nil }
        for key in ["translations", "translation", "translated", "translatedText", "items", "result", "results", "data"] {
            if let nested = dictionary[key],
               let values = translations(fromJSONObject: nested) {
                return values
            }
        }

        let indexedValues = dictionary.compactMap { key, value -> (Int, String)? in
            guard let index = Int(key) else { return nil }
            if let text = value as? String {
                return (index, text.cleanedTranslationText)
            }
            if let nested = value as? [String: Any],
               let text = firstNonEmptyString(in: nested, keys: ["translation", "translated", "translatedText", "text", "value"]) {
                return (index, text.cleanedTranslationText)
            }
            return nil
        }
        guard indexedValues.count == dictionary.count, !indexedValues.isEmpty else { return nil }
        return indexedValues.sorted { $0.0 < $1.0 }.map(\.1).filter { !$0.isEmpty }
    }

    private func parseUnnumberedLines(from content: String, expectedCount: Int) -> [String]? {
        let lines = content
            .strippingCodeFence
            .components(separatedBy: .newlines)
            .map { $0.strippingBulletPrefix.cleanedTranslationText }
            .filter { !$0.isEmpty }
        guard lines.count == expectedCount else { return nil }
        guard !lines.contains(where: looksLikeExplanation) else { return nil }
        return lines
    }

    private func parseSinglePlainText(from content: String) -> String? {
        guard let text = bestEffortSingleTranslation(from: content) else { return nil }
        guard !text.isEmpty,
              !looksLikeExplanation(text) else {
            return nil
        }
        return text
    }

    private func bestEffortSingleTranslation(from content: String) -> String? {
        let cleaned = content.strippingCodeFence.cleanedTranslationText
        guard !cleaned.isEmpty else { return nil }
        if !cleaned.contains("\n") {
            return cleaned
        }

        let lines = cleaned
            .components(separatedBy: .newlines)
            .map { $0.strippingBulletPrefix.cleanedTranslationText }
            .filter { !$0.isEmpty && !looksLikeExplanation($0) }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }

    private func firstNonEmptyString(in dictionary: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private func looksLikeExplanation(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.hasPrefix("here ")
            || lowercased.hasPrefix("sure")
            || lowercased.hasPrefix("translation")
            || lowercased.contains("=>")
    }
}

private extension String {
    var logSnippet: String {
        let clean = replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(clean.prefix(240))
    }

    var strippingCodeFence: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        if !lines.isEmpty {
            lines.removeFirst()
        }
        if lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var cleanedTranslationText: String {
        var text = trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            #"(?i)^here\s+is\s+the\s+translation\s*[:：]\s*"#,
            #"(?i)^translation\s*[:：]\s*"#,
            #"(?i)^translated\s+text\s*[:：]\s*"#,
            #"^译文\s*[:：]\s*"#,
            #"^翻译\s*[:：]\s*"#
        ]
        for pattern in prefixes {
            text = text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return text
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'“”‘’")))
    }

    var strippingBulletPrefix: String {
        replacingOccurrences(of: #"^\s*[-*•]\s+"#, with: "", options: .regularExpression)
    }

    var lineProtocolEscaped: String {
        replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: #" +"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
