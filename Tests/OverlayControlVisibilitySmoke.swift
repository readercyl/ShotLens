import Foundation

@main
struct OverlayControlVisibilitySmoke {
    static func main() throws {
        try assert(.processing, pinned: true, status: true, actions: false)
        try assert(.failure, pinned: true, status: true, actions: false)
        try assert(.success, pinned: false, status: true, actions: true)
        try assert(.success, pinned: true, status: false, actions: false)
        print("Overlay control visibility smoke test passed.")
    }

    private static func assert(
        _ phase: OverlayControlPhase,
        pinned: Bool,
        status: Bool,
        actions: Bool
    ) throws {
        let result = OverlayControlVisibility.resolve(phase: phase, pinned: pinned)
        guard result.statusVisible == status, result.actionsVisible == actions else {
            throw TestFailure("Unexpected visibility for \(phase), pinned=\(pinned): \(result)")
        }
    }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
