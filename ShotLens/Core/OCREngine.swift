import Foundation
import CoreGraphics
import ImageIO

/// OCR 客户端。真正的 Vision OCR 在 ShotLensOCR helper 进程内执行，
/// 避免 Vision/ANE 崩溃时把主 app 一起带退出。
struct OCREngine {
    func recognize(image: CGImage) async throws -> [TextBlock] {
        try Task.checkCancellation()
        let imageURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotLens-OCR-\(UUID().uuidString)")
            .appendingPathExtension("png")
        try writePNG(image, to: imageURL)
        defer { try? FileManager.default.removeItem(at: imageURL) }
        return try await recognize(imageFile: imageURL)
    }

    func recognize(imageFile url: URL) async throws -> [TextBlock] {
        try Task.checkCancellation()
        let helperURL = try locateHelper()
        return try await runHelper(helperURL: helperURL, imageURL: url)
    }

    private func writePNG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            throw OCREngineError.imageEncodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw OCREngineError.imageEncodingFailed
        }
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
        let controller = OCRProcessController()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = helperURL
            // 选区截图已由主进程扩展了 OCR 上下文；边缘文字是否属于用户选区
            // 会在主进程按原始框选区域再次过滤。
            process.arguments = [imageURL.path, "--allow-edge-text"]

            let outputCollector = OCRProcessOutputCollector()
            process.standardOutput = outputCollector.stdout
            process.standardError = outputCollector.stderr

            let resumeState = OCRProcessResumeState(continuation: continuation)
            guard controller.install(process: process, resumeState: resumeState) else { return }

            let timeout = DispatchWorkItem { [weak controller] in
                controller?.timeout()
            }

            process.terminationHandler = { [controller] finishedProcess in
                timeout.cancel()
                outputCollector.finish { outputData, _ in
                    guard finishedProcess.terminationStatus == 0 else {
                        controller.complete(.failure(OCREngineError.helperFailed(statusCode: finishedProcess.terminationStatus)))
                        return
                    }

                    do {
                        let decoded = try JSONDecoder().decode([OCRBlockDTO].self, from: outputData)
                        controller.complete(.success(decoded.map(\.textBlock)))
                    } catch {
                        controller.complete(.failure(OCREngineError.invalidHelperOutput))
                    }
                }
            }

            do {
                outputCollector.start()
                try process.run()
                outputCollector.closeWriters()
                if controller.shouldTerminateStartedProcess() {
                    process.terminate()
                    return
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 45, execute: timeout)
            } catch {
                timeout.cancel()
                outputCollector.closeWriters()
                controller.complete(.failure(error))
            }
            }
        }, onCancel: {
            controller.cancel()
        })
    }
}

private final class OCRProcessOutputCollector: @unchecked Sendable {
    let stdout = Pipe()
    let stderr = Pipe()

    private let group = DispatchGroup()
    private let lock = NSLock()
    private var outputData = Data()
    private var errorData = Data()

    func start() {
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            outputData = data
            lock.unlock()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .utility).async { [self] in
            let data = stderr.fileHandleForReading.readDataToEndOfFile()
            lock.lock()
            errorData = data
            lock.unlock()
            group.leave()
        }
    }

    func closeWriters() {
        try? stdout.fileHandleForWriting.close()
        try? stderr.fileHandleForWriting.close()
    }

    func finish(_ completion: @escaping @Sendable (Data, Data) -> Void) {
        group.notify(queue: .global(qos: .userInitiated)) { [self] in
            lock.lock()
            let output = outputData
            let error = errorData
            lock.unlock()
            completion(output, error)
        }
    }
}

private final class OCRProcessController: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var resumeState: OCRProcessResumeState?
    private var wasCancelled = false

    func install(process: Process, resumeState: OCRProcessResumeState) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !wasCancelled else {
            resumeState.resume(.failure(CancellationError()))
            return false
        }
        self.process = process
        self.resumeState = resumeState
        return true
    }

    func complete(_ result: Result<[TextBlock], Error>) {
        lock.lock()
        guard let state = resumeState else {
            lock.unlock()
            return
        }
        resumeState = nil
        process = nil
        lock.unlock()
        state.resume(result)
    }

    func cancel() {
        lock.lock()
        wasCancelled = true
        let state = resumeState
        let runningProcess = process
        resumeState = nil
        process = nil
        lock.unlock()
        state?.resume(.failure(CancellationError()))
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    func timeout() {
        lock.lock()
        let state = resumeState
        let runningProcess = process
        resumeState = nil
        process = nil
        lock.unlock()
        state?.resume(.failure(OCREngineError.helperTimedOut))
        if runningProcess?.isRunning == true {
            runningProcess?.terminate()
        }
    }

    func shouldTerminateStartedProcess() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return wasCancelled
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

enum OCREngineError: LocalizedError {
    case imageEncodingFailed
    case helperMissing
    case helperTimedOut
    case helperFailed(statusCode: Int32)
    case invalidHelperOutput

    var errorDescription: String? {
        switch self {
        case .imageEncodingFailed:
            return "OCR 临时图像写入失败"
        case .helperMissing:
            return "OCR helper 不存在或不可执行"
        case .helperTimedOut:
            return "OCR helper 执行超时"
        case .helperFailed(let statusCode):
            return "OCR helper 执行失败：\(statusCode)"
        case .invalidHelperOutput:
            return "OCR helper 输出无效"
        }
    }

    var failureKind: PipelineFailureKind {
        switch self {
        case .helperMissing:
            return .ocrHelperMissing
        case .helperTimedOut:
            return .ocrTimedOut
        case .imageEncodingFailed, .helperFailed, .invalidHelperOutput:
            return .ocrFailed
        }
    }
}

extension OCREngineError: ShotLensDiagnosticError {
    var diagnosticCode: String {
        switch self {
        case .imageEncodingFailed:
            return "ocr.image_encoding_failed"
        case .helperMissing:
            return "ocr.helper_missing"
        case .helperTimedOut:
            return "ocr.helper_timed_out"
        case .helperFailed:
            return "ocr.helper_failed"
        case .invalidHelperOutput:
            return "ocr.invalid_output"
        }
    }

    var diagnosticMetadata: [String: String] {
        if case .helperFailed(let statusCode) = self {
            return ["error_number": String(statusCode)]
        }
        return [:]
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
