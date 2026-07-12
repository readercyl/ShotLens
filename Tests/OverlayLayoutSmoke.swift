import CoreGraphics
import Foundation

@main
struct OverlayLayoutSmoke {
    static func main() throws {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 180)
        let source = [
            CGRect(x: 20, y: 20, width: 180, height: 18),
            CGRect(x: 20, y: 44, width: 180, height: 18),
            CGRect(x: 230, y: 22, width: 70, height: 18)
        ]
        let result = OverlayLayoutPlanner.plan(sourceRects: source, in: bounds, minimumSize: CGSize(width: 120, height: 44))
        guard result.count == source.count else { throw TestFailure("Planner changed block count") }
        guard result.allSatisfy({ $0.isFiniteRect && bounds.contains($0) }) else { throw TestFailure("Planner returned invalid or out-of-bounds frames: \(result)") }
        guard !result[0].intersects(result[1]) else { throw TestFailure("Same-column translated paragraphs overlap: \(result)") }
        guard result[2].minX >= 200 else { throw TestFailure("Planner moved the second column into the first") }
        let narrowColumns = OverlayLayoutPlanner.plan(
            sourceRects: [
                CGRect(x: 100, y: 100, width: 30, height: 18),
                CGRect(x: 150, y: 100, width: 30, height: 18)
            ],
            in: bounds,
            minimumSize: CGSize(width: 120, height: 44)
        )
        guard !narrowColumns[0].intersects(narrowColumns[1]) else {
            throw TestFailure("Expanded adjacent columns overlap: \(narrowColumns)")
        }
        print("Overlay layout smoke test passed.")
    }
}

private extension CGRect {
    var isFiniteRect: Bool { [minX, minY, maxX, maxY].allSatisfy(\.isFinite) }
}

private struct TestFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}
