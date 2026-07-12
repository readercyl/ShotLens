import CoreGraphics
import Foundation

enum OverlayLayoutPlanner {
    static func plan(sourceRects: [CGRect], in bounds: CGRect, minimumSize: CGSize) -> [CGRect] {
        guard bounds.width > 0, bounds.height > 0 else { return sourceRects }
        var planned = sourceRects.map { expanded($0, in: bounds, minimumSize: minimumSize) }
        let ordered = sourceRects.indices.sorted {
            if abs(sourceRects[$0].minY - sourceRects[$1].minY) > 6 {
                return sourceRects[$0].minY < sourceRects[$1].minY
            }
            return sourceRects[$0].minX < sourceRects[$1].minX
        }

        for position in ordered.indices {
            let currentIndex = ordered[position]
            guard let nextIndex = ordered.dropFirst(position + 1).first(where: {
                sameColumn(sourceRects[currentIndex], sourceRects[$0])
            }) else { continue }
            guard planned[currentIndex].intersects(planned[nextIndex]) else { continue }

            let boundary = min(
                max((sourceRects[currentIndex].maxY + sourceRects[nextIndex].minY) / 2, planned[currentIndex].minY + 1),
                planned[nextIndex].maxY - 1
            )
            planned[currentIndex].size.height = max(1, boundary - planned[currentIndex].minY)
            let nextMaxY = planned[nextIndex].maxY
            planned[nextIndex].origin.y = boundary
            planned[nextIndex].size.height = max(1, nextMaxY - boundary)
        }

        for leftPosition in sourceRects.indices {
            for rightPosition in sourceRects.indices where rightPosition > leftPosition {
                guard !sameColumn(sourceRects[leftPosition], sourceRects[rightPosition]),
                      planned[leftPosition].intersects(planned[rightPosition]) else { continue }
                let leftIndex = sourceRects[leftPosition].midX <= sourceRects[rightPosition].midX ? leftPosition : rightPosition
                let rightIndex = leftIndex == leftPosition ? rightPosition : leftPosition
                let boundary = (sourceRects[leftIndex].maxX + sourceRects[rightIndex].minX) / 2
                let leftMinX = planned[leftIndex].minX
                let rightMaxX = planned[rightIndex].maxX
                planned[leftIndex].size.width = max(1, boundary - leftMinX)
                planned[rightIndex].origin.x = boundary
                planned[rightIndex].size.width = max(1, rightMaxX - boundary)
            }
        }
        return planned.map { $0.intersection(bounds) }
    }

    private static func expanded(_ rect: CGRect, in bounds: CGRect, minimumSize: CGSize) -> CGRect {
        let width = min(bounds.width, max(rect.width, minimumSize.width))
        let height = min(bounds.height, max(rect.height, minimumSize.height))
        let x = min(max(bounds.minX, rect.midX - width / 2), bounds.maxX - width)
        let y = min(max(bounds.minY, rect.midY - height / 2), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height).integral
    }

    private static func sameColumn(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let overlap = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
        return overlap / max(1, min(lhs.width, rhs.width)) >= 0.35
    }
}
