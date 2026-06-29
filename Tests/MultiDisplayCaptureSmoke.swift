import AppKit

@main
struct MultiDisplayCaptureSmoke {
    @MainActor
    static func main() async throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            throw TestFailure("No screens available")
        }

        for targetScreen in screens {
            let mouseLocation = CGPoint(x: targetScreen.frame.midX, y: targetScreen.frame.midY)
            guard let snapshot = try await ScreenshotCapture()
                .captureFrozenDisplay(containing: mouseLocation) else {
                throw TestFailure("Expected a frozen screenshot")
            }

            guard snapshot.screenRect == targetScreen.frame else {
                throw TestFailure(
                    "Expected mouse screen \(targetScreen.frame), got \(snapshot.screenRect)"
                )
            }

            let expectedWidth = Int(ceil(targetScreen.frame.width * targetScreen.backingScaleFactor))
            let expectedHeight = Int(ceil(targetScreen.frame.height * targetScreen.backingScaleFactor))
            guard snapshot.image.width == expectedWidth,
                  snapshot.image.height == expectedHeight else {
                throw TestFailure(
                    "Expected \(expectedWidth)x\(expectedHeight), got \(snapshot.image.width)x\(snapshot.image.height)"
                )
            }
        }

        print("Multi-display capture smoke test passed.")
    }
}

private struct TestFailure: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
