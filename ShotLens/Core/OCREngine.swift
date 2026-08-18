import Foundation
import CoreGraphics

/// OCR 客户端。真正的 Vision OCR 在 ShotLensOCR helper 进程内执行，
/// 避免 Vision/ANE 崩溃时把主 app 一起带退出。
struct OCREngine {
    func recognize(imageFile url: URL) async throws -> [TextBlock] {
        let helperURL = try locateHelper()
        return try await runHelper(helperURL: helperURL, imageURL: url)
    }

    private func locateHelper() throws -> URL {
        guard let executableURL = Bundle.main.executableURL else {
            throw OCREngineError.helperMissing
        }

        let helperURL = executableURL
            .deletingLastPathComponent()
            .appendingPathComponent("ShotLensOCR")

        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw OCREngineError.helperMissing
        }

        return helperURL
    }

    private func runHelper(helperURL: URL, imageURL: URL) async throws -> [TextBlock] {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = helperURL
            // 选区截图已由主进程扩展了 OCR 上下文；边缘文字是否属于用户选区
            // 会在主进程按原始框选区域再次过滤。
            process.arguments = [imageURL.path, "--allow-edge-text"]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            let resumeState = OCRProcessResumeState(continuation: continuation)

            let timeout = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { finishedProcess in
                timeout.cancel()

                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errorText = String(data: errorData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                guard finishedProcess.terminationStatus == 0 else {
                    resumeState.resume(.failure(OCREngineError.helperFailed(errorText)))
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode([OCRBlockDTO].self, from: outputData)
                    resumeState.resume(.success(decoded.map(\.textBlock)))
                } catch {
                    resumeState.resume(.failure(OCREngineError.invalidHelperOutput(error.localizedDescription)))
                }
            }

            do {
                try process.run()
                DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: timeout)
            } catch {
                timeout.cancel()
                resumeState.resume(.failure(error))
            }
        }
    }
}

private final class OCRProcessResumeState: @unchecked Sendable {
    private let lock = NSLock()
    private var hasResumed = false
    private let continuation: CheckedContinuation<[TextBlock], Error>

    init(continuation: CheckedContinuation<[TextBlock], Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<[TextBlock], Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        hasResumed = true

        switch result {
        case .success(let blocks):
            continuation.resume(returning: blocks)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private struct OCRBlockDTO: Decodable {
    let text: String
    let boundingBox: OCRRectDTO
    let detectedLanguage: String
    let visualStyle: TextBlockVisualStyle?
    let englishRuns: [OCRRunDTO]?

    var textBlock: TextBlock {
        TextBlock(
            text: text.normalizedOCRText,
            boundingBox: boundingBox.cgRect,
            detectedLanguage: detectedLanguage,
            visualStyle: visualStyle ?? .unknown,
            englishRuns: (englishRuns ?? []).map(\.textRun)
        )
    }
}

private struct OCRRunDTO: Decodable {
    let text: String
    let boundingBox: OCRRectDTO

    var textRun: TextRun {
        TextRun(text: text, boundingBox: boundingBox.cgRect)
    }
}

private struct OCRRectDTO: Decodable {
    let x: CGFloat
    let y: CGFloat
    let width: CGFloat
    let height: CGFloat

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

private enum OCREngineError: LocalizedError {
    case helperMissing
    case helperFailed(String)
    case invalidHelperOutput(String)

    var errorDescription: String? {
        switch self {
        case .helperMissing:
            return "OCR helper 不存在或不可执行"
        case .helperFailed(let message):
            return message.isEmpty ? "OCR helper 执行失败" : message
        case .invalidHelperOutput(let message):
            return "OCR helper 输出无效：\(message)"
        }
    }
}

private extension String {
    var normalizedOCRText: String {
        var value = replacingOccurrences(
            of: #"\bAl\b"#,
            with: "AI",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\b[Aa] im tokens\b"#,
            with: "a 1m tokens",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\bim tokens\b"#,
            with: "1m tokens",
            options: .regularExpression
        )
        return value
    }
}
