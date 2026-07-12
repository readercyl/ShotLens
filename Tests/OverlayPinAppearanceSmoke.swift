import Foundation

@main
struct OverlayPinAppearanceSmoke {
    static func main() throws {
        guard OverlayPinAppearance.usesDarkSymbol(backgroundLuminance: 0.8) else {
            throw TestFailure("Light backgrounds must use a black pin")
        }
        guard !OverlayPinAppearance.usesDarkSymbol(backgroundLuminance: 0.2) else {
            throw TestFailure("Dark backgrounds must use a white pin")
        }
        guard OverlayPinAppearance.symbolRotationDegrees(isPinned: false) == -45 else {
            throw TestFailure("Unpinned pin must stay vertical")
        }
        guard OverlayPinAppearance.symbolRotationDegrees(isPinned: true) == 0 else {
            throw TestFailure("Pinned pin must rotate 45 degrees")
        }
        print("Overlay pin appearance smoke test passed.")
    }
}

struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
