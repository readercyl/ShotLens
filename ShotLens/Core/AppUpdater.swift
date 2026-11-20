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
    static let repository = "readercyl/ShotLens"
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    static let automaticCheckInterval: TimeInterval = 24 * 60 * 60

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
        guard Bundle(url: appURL)?.bundleIdentifier != "com.qingcheng.shotlens.mac.development" else {
            throw AppUpdaterError.developmentBuild
        }
        // 脚本第一步就会因为不可写而失败，此时应用已经退出，用户会以为应用消失了。
        let parentDirectory = appURL.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parentDirectory.path) else {
            throw AppUpdaterError.appNotWritable
        }

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

    static func shouldAutomaticallyCheck(lastCheckedAt: Date?, now: Date = Date()) -> Bool {
        guard let lastCheckedAt else { return true }
        return now.timeIntervalSince(lastCheckedAt) >= automaticCheckInterval
    }

    static func canAutomaticallyInstall(appURL: URL = Bundle.main.bundleURL) -> Bool {
        let parent = appURL.deletingLastPathComponent().standardizedFileURL
        if parent.path == "/Applications" { return true }
        let userApplications = FileManager.default.urls(
            for: .applicationDirectory,
            in: .userDomainMask
        ).first?.standardizedFileURL
        return parent == userApplications
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
        // v1.2.3-rc1 / v1.2.3+7 这类标签按主版本号比较
        let core = version.split(whereSeparator: { $0 == "-" || $0 == "+" }).first.map(String.init) ?? version
        let normalized = core.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        let parts = normalized.split(separator: ".")
        guard parts.allSatisfy({ Int($0) != nil }) else { return [] }
        return parts.compactMap { Int($0) }
    }

    static let updaterScript = """
    #!/usr/bin/env bash
    set -euo pipefail

    APP_PATH="$1"
    DMG_PATH="$2"
    LOG_PATH="${TMPDIR:-/tmp}/shotlens-updater.log"
    APP_PARENT="$(dirname "$APP_PATH")"
    UPDATE_ID="$$-$(date +%s)"
    STAGING_APP="$APP_PARENT/.ShotLens-update-$UPDATE_ID.app"
    BACKUP_APP="$APP_PARENT/.ShotLens-backup-$UPDATE_ID.app"

    log() {
      printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_PATH"
    }

    log "start app=$APP_PATH dmg=$DMG_PATH"
    case "$APP_PATH" in
      *.app) ;;
      *) log "target is not an app bundle"; exit 1 ;;
    esac
    test -d "$APP_PATH"
    test -w "$APP_PARENT"
    APP_EXECUTABLE="$APP_PATH/Contents/MacOS/ShotLens"
    app_is_running() {
      ps -axww -o comm= | awk -v path="$APP_EXECUTABLE" '$0 == path { found=1 } END { exit !found }'
    }
    for _ in $(seq 1 40); do
      if ! app_is_running; then
        break
      fi
      sleep 0.25
    done
    if app_is_running; then
      log "old app process still running"
      exit 1
    fi

    MOUNT_DIR="$(mktemp -d)"
    READY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/shotlens-ready.XXXXXXXX")"
    READY_FILE="$READY_DIR/ready"
    cleanup() {
      hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
      rmdir "$MOUNT_DIR" 2>/dev/null || true
      rm -f "$READY_FILE"
      rmdir "$READY_DIR" 2>/dev/null || true
      rm -rf "$STAGING_APP" 2>/dev/null || true
    }
    trap cleanup EXIT

    restore_backup() {
      log "restoring previous app"
      rm -rf "$APP_PATH" 2>/dev/null || true
      if ! mv "$BACKUP_APP" "$APP_PATH"; then
        log "restore failed; backup retained at $BACKUP_APP"
        return 1
      fi
    }

    hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" >/dev/null
    SOURCE_APP="$MOUNT_DIR/ShotLens.app"
    test -d "$SOURCE_APP"
    test -x "$SOURCE_APP/Contents/MacOS/ShotLens"

    CURRENT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")"
    NEW_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")"
    test -n "$CURRENT_BUNDLE_ID"
    test "$CURRENT_BUNDLE_ID" = "$NEW_BUNDLE_ID"
    log "staging app"
    ditto "$SOURCE_APP" "$STAGING_APP"
    test -x "$STAGING_APP/Contents/MacOS/ShotLens"
    xattr -cr "$STAGING_APP"
    /usr/bin/codesign --verify --deep --strict "$STAGING_APP"
    CURRENT_REQUIREMENT="$(/usr/bin/codesign -dr - "$APP_PATH" 2>&1 | sed -n 's/^.*designated => //p')"
    test -n "$CURRENT_REQUIREMENT"
    /usr/bin/codesign --verify --deep --strict -R="$CURRENT_REQUIREMENT" "$STAGING_APP"
    mv "$APP_PATH" "$BACKUP_APP"
    if ! mv "$STAGING_APP" "$APP_PATH"; then
      restore_backup
      exit 1
    fi
    xattr -dr com.apple.quarantine "$APP_PATH" 2>/dev/null || true
    log "launching app"
    if /usr/bin/open -n "$APP_PATH" --args --shotlens-update-ready "$READY_FILE"; then
      for _ in $(seq 1 40); do
        if [[ -s "$READY_FILE" ]]; then
          READY_PID="$(cat "$READY_FILE")"
          if [[ "$READY_PID" =~ ^[1-9][0-9]*$ ]]; then
            sleep 1
            if [[ "$(ps -p "$READY_PID" -ww -o comm=)" == "$APP_EXECUTABLE" ]]; then
              rm -rf "$BACKUP_APP"
              rm -f "$DMG_PATH"
              log "update complete"
              exit 0
            fi
          fi
          break
        fi
        sleep 0.25
      done
    fi
    if app_is_running; then
      log "startup not confirmed; running app untouched, backup retained at $BACKUP_APP"
    else
      log "startup not confirmed; rolling back"
      restore_backup
      /usr/bin/open -n "$APP_PATH" 2>/dev/null || true
    fi
    exit 1
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
    case developmentBuild
    case appNotWritable

    var errorDescription: String? {
        switch self {
        case .downloadFailed:
            return "下载安装包失败"
        case .developmentBuild:
            return "开发版不能安装正式更新"
        case .appNotWritable:
            return "当前位置没有写入权限，请把应用移到「应用程序」后再升级"
        }
    }
}
