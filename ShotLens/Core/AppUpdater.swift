import AppKit
import Foundation

struct AppUpdate: Equatable, CustomStringConvertible {
    let version: String
    let dmgURL: URL
    let releaseNotesURL: URL

    var description: String {
        "\(version) \(dmgURL.absoluteString)"
    }
}

enum AppUpdateCheckResult: CustomStringConvertible {
    case available(AppUpdate)
    case upToDate
    case failed(String)

    var description: String {
        switch self {
        case .available(let update):
            return "available(\(update))"
        case .upToDate:
            return "upToDate"
        case .failed(let message):
            return "failed(\(message))"
        }
    }
}

struct AppUpdater {
    static let repository = "qcsidios/ShotLens"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!

    let currentVersion: String
    let session: URLSession

    init(
        currentVersion: String = AppUpdater.bundleShortVersion,
        session: URLSession = .shared
    ) {
        self.currentVersion = currentVersion
        self.session = session
    }

    func checkForUpdate() async -> AppUpdateCheckResult {
        do {
            var request = URLRequest(url: Self.latestReleaseURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("ShotLens", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 12

            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return .failed("无法连接更新服务器")
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard Self.isValidVersionTag(release.tagName) else {
                return .failed("更新版本号无效")
            }

            guard Self.compareVersions(release.tagName, currentVersion) == .orderedDescending else {
                return .upToDate
            }

            guard let asset = release.assets.first(where: { asset in
                asset.name.hasPrefix("ShotLens-")
                    && asset.name.hasSuffix(".dmg")
                    && asset.name.contains(release.tagName)
            }) else {
                return .failed("未找到可安装的 DMG")
            }

            return .available(AppUpdate(
                version: release.tagName,
                dmgURL: asset.browserDownloadURL,
                releaseNotesURL: release.htmlURL
            ))
        } catch {
            return .failed("无法连接更新服务器")
        }
    }

    func download(_ update: AppUpdate) async throws -> URL {
        var request = URLRequest(url: update.dmgURL)
        request.setValue("ShotLens", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 60

        let (temporaryURL, response) = try await session.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppUpdaterError.downloadFailed
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShotLens-\(update.version).dmg")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    @MainActor
    func installDownloadedUpdate(from dmgURL: URL, replacing appURL: URL = Bundle.main.bundleURL) throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shotlens-updater-\(UUID().uuidString).sh")
        try Self.updaterScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path, appURL.path, dmgURL.path]
        try process.run()

        NSApp.terminate(nil)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = numericVersionParts(lhs)
        let right = numericVersionParts(rhs)
        for index in 0..<max(left.count, right.count) {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static var bundleShortVersion: String {
        let shortVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let normalized = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return normalized.isEmpty ? "0.0.0" : normalized
    }

    private static func isValidVersionTag(_ tag: String) -> Bool {
        numericVersionParts(tag).count >= 2
    }

    private static func numericVersionParts(_ version: String) -> [Int] {
        let normalized = version.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = normalized.split(separator: ".")
        guard parts.allSatisfy({ Int($0) != nil }) else { return [] }
        return parts.compactMap { Int($0) }
    }

    private static let updaterScript = """
    #!/usr/bin/env bash
    set -euo pipefail

    APP_PATH="$1"
    DMG_PATH="$2"

    sleep 1
    MOUNT_DIR="$(mktemp -d)"
    cleanup() {
      hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
      rmdir "$MOUNT_DIR" 2>/dev/null || true
    }
    trap cleanup EXIT

    hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null
    SOURCE_APP="$MOUNT_DIR/ShotLens.app"
    test -d "$SOURCE_APP"

    rm -rf "$APP_PATH"
    ditto "$SOURCE_APP" "$APP_PATH"
    xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
    open "$APP_PATH"
    """

    private struct GitHubRelease: Decodable {
        let tagName: String
        let htmlURL: URL
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case browserDownloadURL = "browser_download_url"
        }
    }
}

enum AppUpdaterError: LocalizedError {
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "下载安装包失败"
        }
    }
}
