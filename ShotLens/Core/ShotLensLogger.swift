import Foundation
import os

protocol ShotLensDiagnosticError {
    var diagnosticCode: String { get }
    var diagnosticMetadata: [String: String] { get }
}

extension ShotLensDiagnosticError {
    var diagnosticMetadata: [String: String] { [:] }
}

struct ShotLensRunContext: Sendable {
    let id: String
    let startedUptime: TimeInterval

    init(id: String = UUID().uuidString.lowercased(), startedUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        self.id = id
        self.startedUptime = startedUptime
    }

    func elapsedMilliseconds(since uptime: TimeInterval? = nil) -> Int {
        let start = uptime ?? startedUptime
        return max(0, Int(((ProcessInfo.processInfo.systemUptime - start) * 1_000).rounded()))
    }
}

enum ShotLensLogLevel: String, Sendable {
    case info
    case warning
    case error
}

enum ShotLensLogger {
    @TaskLocal static var currentRun: ShotLensRunContext?
    private static let queue = DispatchQueue(label: "ShotLensLogger")
    private static let systemLogger = Logger(subsystem: "com.qingcheng.shotlens.mac", category: "diagnostics")
    private static let formatter = ISO8601DateFormatter()
    private static let maxFileBytes: UInt64 = 5 * 1_024 * 1_024
    private static let backupCount = 3
    private static let allowedFieldKeys: Set<String> = [
        "action", "app_version", "attempt", "batch_count", "cache_hit", "character_count",
        "completed_count", "concurrency", "context_count", "display_block_count", "duration_ms",
        "enhanced_pass", "endpoint_host", "error_code", "error_domain", "error_number", "event_source",
        "http_status", "image_height", "image_width", "ocr_block_count", "os_version", "outcome",
        "overflow_count", "provider", "recovery", "render_mode", "scenario", "screen_count",
        "selected_block_count", "selection_height", "selection_width", "semantic_block_count", "stage",
        "total_count", "total_duration_ms", "trigger", "render_duration_ms", "font_size",
        "required_height", "available_height"
    ]

    static var diagnosticDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/ShotLens", isDirectory: true)
    }

    private static var diagnosticFileURL: URL {
        diagnosticDirectoryURL.appendingPathComponent("ShotLens.ndjson")
    }

    static func startRun(trigger: String) -> ShotLensRunContext {
        let run = ShotLensRunContext()
        event("run_started", run: run, stage: "flow", fields: ["trigger": trigger])
        return run
    }

    static func withRun<T>(
        _ run: ShotLensRunContext,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $currentRun.withValue(run, operation: operation)
    }

    static func event(
        _ name: String,
        run: ShotLensRunContext? = nil,
        level: ShotLensLogLevel = .info,
        stage: String? = nil,
        outcome: String? = nil,
        fields: [String: String] = [:],
        error: Error? = nil,
        function: String = #function,
        line: Int = #line
    ) {
        var safeFields = sanitizedFields(fields)
        if let stage { safeFields["stage"] = stage }
        if let outcome { safeFields["outcome"] = outcome }
        if let error { safeFields.merge(errorMetadata(for: error)) { _, new in new } }

        let safeName = sanitizedEventName(name)
        let effectiveRun = run ?? currentRun
        queue.async {
            var object: [String: Any] = [
                "timestamp": formatter.string(from: Date()),
                "level": level.rawValue,
                "event": safeName,
                "source": "\(function):\(line)"
            ]
            if let run = effectiveRun {
                object["run_id"] = run.id
            }
            for (key, value) in safeFields {
                object[key] = value
            }

            guard JSONSerialization.isValidJSONObject(object),
                  let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
                systemLogger.error("diagnostic serialization failed")
                return
            }
            var entry = data
            entry.append(0x0A)
            systemLogger.log("\(String(decoding: data, as: UTF8.self), privacy: .public)")
            write(entry)
        }
    }

    /// 旧调用保留为无内容的来源事件，避免把任意字符串继续写入诊断文件。
    /// 新代码应使用 event(_:run:level:stage:outcome:fields:error:)。
    static func log(
        _ message: String,
        error: Error? = nil,
        function: String = #function,
        line: Int = #line
    ) {
        _ = message
        event(
            "legacy_event",
            level: error == nil ? .info : .error,
            fields: ["event_source": function],
            error: error,
            function: function,
            line: line
        )
    }

    static func latestDiagnosticText(maxLines: Int = 240) -> String? {
        queue.sync {
            guard let data = try? Data(contentsOf: diagnosticFileURL),
                  let text = String(data: data, encoding: .utf8) else { return nil }
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
            return lines.suffix(max(1, maxLines)).joined(separator: "\n")
        }
    }

    static func clearDiagnostics() throws {
        try queue.sync {
            let fileManager = FileManager.default
            let urls = [diagnosticFileURL]
                + (1...backupCount).map { diagnosticFileURL.appendingPathExtension(String($0)) }
                + [diagnosticDirectoryURL.appendingPathComponent("ShotLens.log")]
            for url in urls where fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    static func ensureDiagnosticDirectory() throws {
        try queue.sync {
            let fileManager = FileManager.default
            try fileManager.createDirectory(at: diagnosticDirectoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: diagnosticDirectoryURL.path)
        }
    }

    static func errorMetadata(for error: Error) -> [String: String] {
        if let diagnostic = error as? ShotLensDiagnosticError {
            var metadata = sanitizedFields(diagnostic.diagnosticMetadata)
            metadata["error_code"] = String(diagnostic.diagnosticCode.prefix(80))
            return metadata
        }
        if error is CancellationError {
            return ["error_code": "task.cancelled"]
        }
        let nsError = error as NSError
        return [
            "error_code": "system.error",
            "error_domain": String(nsError.domain.prefix(80)),
            "error_number": String(nsError.code)
        ]
    }

    static func sanitizedFieldsForTesting(_ fields: [String: String]) -> [String: String] {
        sanitizedFields(fields)
    }

    private static func sanitizedFields(_ fields: [String: String]) -> [String: String] {
        fields.reduce(into: [:]) { result, element in
            guard allowedFieldKeys.contains(element.key) else { return }
            let value = element.value
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            result[element.key] = String(value.prefix(160))
        }
    }

    private static func sanitizedEventName(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        let scalars = name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "_" }
        let value = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return value.isEmpty ? "unknown_event" : String(value.prefix(80))
    }

    private static func write(_ entry: Data) {
        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: diagnosticDirectoryURL, withIntermediateDirectories: true)
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: diagnosticDirectoryURL.path)
            try rotateIfNeeded(adding: UInt64(entry.count), fileManager: fileManager)
            if !fileManager.fileExists(atPath: diagnosticFileURL.path) {
                fileManager.createFile(
                    atPath: diagnosticFileURL.path,
                    contents: nil,
                    attributes: [.posixPermissions: 0o600]
                )
            }
            let handle = try FileHandle(forWritingTo: diagnosticFileURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: entry)
            try handle.close()
        } catch {
            systemLogger.error("diagnostic write failed code=\((error as NSError).code)")
        }
    }

    private static func rotateIfNeeded(adding bytes: UInt64, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: diagnosticFileURL.path) else { return }
        let attributes = try fileManager.attributesOfItem(atPath: diagnosticFileURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        guard currentSize + bytes > maxFileBytes else { return }

        for index in stride(from: backupCount, through: 1, by: -1) {
            let target = diagnosticFileURL.appendingPathExtension(String(index))
            if fileManager.fileExists(atPath: target.path) {
                try fileManager.removeItem(at: target)
            }
            let source = index == 1
                ? diagnosticFileURL
                : diagnosticFileURL.appendingPathExtension(String(index - 1))
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: target)
            }
        }
    }
}
