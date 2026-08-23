import Foundation
import CoreGraphics
import Darwin

@main
struct OCRProcessSmoke {
    static func main() async throws {
        if URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent == "ShotLensOCR" {
            try runFakeHelper()
            return
        }

        let image = try makeImage()
        try await assertLargeOutputDoesNotDeadlock(image: image)
        try await assertCancellationStopsHelper(image: image)
        print("OCR process smoke test passed.")
    }

    private static func runFakeHelper() throws {
        if ProcessInfo.processInfo.environment["SHOTLENS_OCR_TEST_MODE"] == "sleep" {
            Thread.sleep(forTimeInterval: 10)
            return
        }

        let block: [String: Any] = [
            "text": "Large OCR output",
            "boundingBox": ["x": 1, "y": 1, "width": 40, "height": 12],
            "detectedLanguage": "en"
        ]
        let data = try JSONSerialization.data(
            withJSONObject: Array(repeating: block, count: 3_000)
        )
        FileHandle.standardOutput.write(data)
    }

    private static func assertLargeOutputDoesNotDeadlock(image: CGImage) async throws {
        unsetenv("SHOTLENS_OCR_TEST_MODE")
        let before = temporaryOCRFiles()
        let startedAt = ProcessInfo.processInfo.systemUptime
        let blocks = try await OCREngine().recognize(image: image)
        let duration = ProcessInfo.processInfo.systemUptime - startedAt
        guard blocks.count == 3_000 else {
            throw TestFailure("Expected all large helper output, got \(blocks.count) blocks")
        }
        guard duration < 5 else {
            throw TestFailure("Large helper output should be drained while the process is running")
        }
        guard temporaryOCRFiles().subtracting(before).isEmpty else {
            throw TestFailure("OCR attempt must remove its unique temporary PNG")
        }
    }

    private static func assertCancellationStopsHelper(image: CGImage) async throws {
        setenv("SHOTLENS_OCR_TEST_MODE", "sleep", 1)
        defer { unsetenv("SHOTLENS_OCR_TEST_MODE") }

        let before = temporaryOCRFiles()
        let startedAt = ProcessInfo.processInfo.systemUptime
        let task = Task { try await OCREngine().recognize(image: image) }
        try await Task.sleep(nanoseconds: 120_000_000)
        task.cancel()

        do {
            _ = try await task.value
            throw TestFailure("Cancelled OCR must not return a successful result")
        } catch is CancellationError {
            // Expected.
        }

        guard ProcessInfo.processInfo.systemUptime - startedAt < 2 else {
            throw TestFailure("Cancelling OCR must terminate the helper promptly")
        }
        guard temporaryOCRFiles().subtracting(before).isEmpty else {
            throw TestFailure("Cancelled OCR must remove its temporary PNG")
        }
    }

    private static func makeImage() throws -> CGImage {
        guard let context = CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let image = context.makeImage() else {
            throw TestFailure("Could not create OCR test image")
        }
        return image
    }

    private static func temporaryOCRFiles() -> Set<String> {
        let directory = FileManager.default.temporaryDirectory
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.filter { $0.hasPrefix("ShotLens-OCR-") && $0.hasSuffix(".png") })
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
