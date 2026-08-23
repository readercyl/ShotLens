import Foundation

@main
struct PipelineDiagnosticsSmoke {
    static func main() throws {
        try assertScenarioClassification()
        try assertFailurePresentation()
        try assertAttemptGate()
        try assertDiagnosticRedaction()
        print("Pipeline diagnostics smoke test passed.")
    }

    private static func assertScenarioClassification() throws {
        guard TranslationScenario.classify(sourceTexts: ["Settings"]) == .word,
              TranslationScenario.classify(sourceTexts: ["Open account settings"]) == .smallScattered,
              TranslationScenario.classify(sourceTexts: Array(repeating: "A paragraph with several complete sentences.", count: 12)) == .largeRegion else {
            throw TestFailure("Translation scenarios must distinguish word, small, and large selections")
        }
    }

    private static func assertFailurePresentation() throws {
        let ocr = PipelineFailurePresentation.make(kind: .ocrFailed)
        guard ocr.title == "文字识别失败",
              ocr.actionTitle == "重新识别",
              ocr.recovery == .retryOCR else {
            throw TestFailure("OCR failures must offer OCR retry")
        }

        let empty = PipelineFailurePresentation.make(kind: .noText)
        guard empty.actionTitle == "重新框选", empty.recovery == .reselect else {
            throw TestFailure("Empty OCR results must offer reselection")
        }

        let auth = PipelineFailurePresentation.make(kind: .authenticationFailed)
        guard auth.actionTitle == "打开设置", auth.recovery == .openSettings else {
            throw TestFailure("Authentication failures must open settings")
        }

        let notFound = PipelineFailurePresentation.make(kind: .endpointOrModelNotFound)
        guard notFound.title == "接口或模型不存在",
              notFound.actionTitle == "打开设置",
              notFound.recovery == .openSettings else {
            throw TestFailure("Missing endpoints or models must point to settings")
        }

        let partial = PipelineFailurePresentation.make(kind: .partialTranslation, completedCount: 18, totalCount: 24)
        guard partial.title == "已完成 18/24",
              partial.actionTitle == "重试未完成项",
              partial.recovery == .retryTranslation else {
            throw TestFailure("Partial translations must expose completion count and bounded retry")
        }
    }

    private static func assertAttemptGate() throws {
        var gate = PipelineAttemptGate()
        guard let first = gate.begin(), gate.begin() == nil else {
            throw TestFailure("A running translation attempt must reject duplicate starts")
        }
        gate.finish(first)
        guard gate.begin() != nil else {
            throw TestFailure("A completed translation attempt must allow the next start")
        }
        gate.cancel()
        guard !gate.isRunning else {
            throw TestFailure("Cancellation must release the translation gate")
        }
    }

    private static func assertDiagnosticRedaction() throws {
        let fields = ShotLensLogger.sanitizedFieldsForTesting([
            "stage": "translation",
            "duration_ms": "120",
            "source_text": "private OCR text",
            "response_body": "private provider body",
            "api_key": "secret-key"
        ])
        guard fields["stage"] == "translation",
              fields["duration_ms"] == "120",
              fields["source_text"] == nil,
              fields["response_body"] == nil,
              fields["api_key"] == nil else {
            throw TestFailure("Diagnostics must whitelist safe fields and drop user content")
        }

        let metadata = ShotLensLogger.errorMetadata(for: PrivateDiagnosticError())
        guard metadata["error_code"] == "test.private",
              !metadata.values.contains(where: { $0.contains("private response body") }) else {
            throw TestFailure("Diagnostics must never serialize localized error descriptions")
        }
    }
}

private struct PrivateDiagnosticError: LocalizedError, ShotLensDiagnosticError {
    var diagnosticCode: String { "test.private" }
    var diagnosticMetadata: [String: String] { [:] }
    var errorDescription: String? { "private response body" }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
