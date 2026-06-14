import Foundation

@main
struct AppUpdaterSmoke {
    static func main() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockGitHubProtocol.self]
        let session = URLSession(configuration: configuration)

        try await assertFindsNewerRelease(session: session)
        try await assertCurrentReleaseIsUpToDate(session: session)
        try await assertMissingDMGIsUnavailable(session: session)
        try await assertInvalidTagIsUnavailable(session: session)

        print("App updater smoke test passed.")
    }

    private static func assertFindsNewerRelease(session: URLSession) async throws {
        MockGitHubProtocol.responseBody = latestReleaseJSON(
            tag: "v0.7.0",
            assetName: "ShotLens-v0.7.0.dmg",
            assetURL: "https://downloads.example/ShotLens-v0.7.0.dmg"
        )
        let updater = AppUpdater(currentVersion: "0.6.0", session: session)
        let result = await updater.checkForUpdate()

        guard case .available(let update) = result else {
            throw TestFailure("Expected newer GitHub release to be available, got \(result)")
        }
        guard update.version == "v0.7.0",
              update.dmgURL.absoluteString == "https://downloads.example/ShotLens-v0.7.0.dmg" else {
            throw TestFailure("Unexpected update payload: \(update)")
        }
    }

    private static func assertCurrentReleaseIsUpToDate(session: URLSession) async throws {
        MockGitHubProtocol.responseBody = latestReleaseJSON(
            tag: "v0.6.0",
            assetName: "ShotLens-v0.6.0.dmg",
            assetURL: "https://downloads.example/ShotLens-v0.6.0.dmg"
        )
        let updater = AppUpdater(currentVersion: "0.6.0", session: session)
        let result = await updater.checkForUpdate()

        guard case .upToDate = result else {
            throw TestFailure("Expected matching release to be up to date, got \(result)")
        }
    }

    private static func assertMissingDMGIsUnavailable(session: URLSession) async throws {
        MockGitHubProtocol.responseBody = latestReleaseJSON(
            tag: "v0.7.0",
            assetName: "ShotLens-v0.7.0.zip",
            assetURL: "https://downloads.example/ShotLens-v0.7.0.zip"
        )
        let updater = AppUpdater(currentVersion: "0.6.0", session: session)
        let result = await updater.checkForUpdate()

        guard case .failed = result else {
            throw TestFailure("Expected release without DMG asset to fail, got \(result)")
        }
    }

    private static func assertInvalidTagIsUnavailable(session: URLSession) async throws {
        MockGitHubProtocol.responseBody = latestReleaseJSON(
            tag: "latest",
            assetName: "ShotLens-latest.dmg",
            assetURL: "https://downloads.example/ShotLens-latest.dmg"
        )
        let updater = AppUpdater(currentVersion: "0.6.0", session: session)
        let result = await updater.checkForUpdate()

        guard case .failed = result else {
            throw TestFailure("Expected invalid release tag to fail, got \(result)")
        }
    }

    private static func latestReleaseJSON(tag: String, assetName: String, assetURL: String) -> String {
        """
        {
          "tag_name": "\(tag)",
          "html_url": "https://github.com/qcsidios/ShotLens/releases/tag/\(tag)",
          "assets": [
            {
              "name": "\(assetName)",
              "browser_download_url": "\(assetURL)"
            }
          ]
        }
        """
    }
}

private final class MockGitHubProtocol: URLProtocol {
    static var responseBody = "{}"

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.github.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(Self.responseBody.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
