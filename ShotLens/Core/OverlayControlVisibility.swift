import Foundation

enum OverlayControlPhase {
    case processing
    case success
    case failure
}

struct OverlayControlVisibility: Equatable {
    let statusVisible: Bool
    let actionsVisible: Bool

    static func resolve(phase: OverlayControlPhase, pinned: Bool) -> OverlayControlVisibility {
        switch phase {
        case .processing, .failure:
            return OverlayControlVisibility(statusVisible: true, actionsVisible: false)
        case .success:
            return OverlayControlVisibility(statusVisible: !pinned, actionsVisible: !pinned)
        }
    }
}
