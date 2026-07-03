import CoreGraphics
import Foundation

enum TextLayoutOptimizer {
    static func merge(_ blocks: [TextBlock]) -> [TextBlock] {
        let readable = blocks
            .map { $0.trimmingText() }
            .filter { !$0.text.isEmpty && !$0.text.isMostlyPunctuation }
        let filtered = readable
            .filter { readable.count == 1 || !$0.isLikelyIconBlock }
            .sorted { lhs, rhs in
                if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 8 {
                    return lhs.boundingBox.minY < rhs.boundingBox.minY
                }
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }

        guard !filtered.isEmpty else { return [] }
        let layoutKind = TextLayoutKind.classify(filtered)

        if layoutKind.preservesIndividualRows {
            return filtered
        }

        var groups: [TextLayoutGroup] = []
        for block in filtered {
            if let index = groups.indices.last(where: { groups[$0].canAccept(block, layoutKind: layoutKind) }) {
                groups[index].append(block)
            } else {
                groups.append(TextLayoutGroup(block))
            }
        }

        return groups.map(\.textBlock)
    }
}

enum TextLayoutKind {
    case shortText
    case menuList
    case paragraph
    case article
    case mixed

    var preservesIndividualRows: Bool {
        switch self {
        case .shortText, .menuList:
            return true
        case .paragraph, .article, .mixed:
            return false
        }
    }

    static func classify(_ blocks: [TextBlock]) -> TextLayoutKind {
        guard blocks.count > 1 else { return .shortText }

        let heights = blocks.map { max(1, $0.boundingBox.height) }.sorted()
        let medianHeight = heights[heights.count / 2]
        let minHeight = heights.first ?? medianHeight
        let maxHeight = heights.last ?? medianHeight
        let heightSpread = maxHeight / max(1, minHeight)
        let shortTextRatio = Double(blocks.filter { $0.text.trimmedCount <= 36 }.count) / Double(blocks.count)
        let longTextRatio = Double(blocks.filter { $0.text.trimmedCount >= 72 }.count) / Double(blocks.count)
        let sentenceFragmentRatio = Double(blocks.filter { $0.text.looksLikeSentenceFragment }.count) / Double(blocks.count)
        let styleMetrics = VisualStyleMetrics(blocks: blocks)
        let rowLikeRatio = Double(blocks.filter { block in
            let rect = block.boundingBox
            return rect.height <= medianHeight * 1.45 && rect.width > rect.height * 1.4
        }.count) / Double(blocks.count)
        let verticalGaps = blocks.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
            .adjacentPairs()
            .map { max(0, $1.boundingBox.minY - $0.boundingBox.maxY) }
        let regularGapRatio = verticalGaps.isEmpty
            ? 1.0
            : Double(verticalGaps.filter { $0 <= medianHeight * 1.2 }.count) / Double(verticalGaps.count)

        if blocks.count <= 2 && shortTextRatio == 1 {
            return .shortText
        }

        if blocks.count >= 3,
           sentenceFragmentRatio >= 0.45,
           regularGapRatio >= 0.55 {
            return .paragraph
        }

        if blocks.count >= 3,
           shortTextRatio >= 0.72,
           rowLikeRatio >= 0.65,
           regularGapRatio >= 0.65,
           styleMetrics.fontSpread <= 1.5,
           heightSpread <= 1.9 {
            return .menuList
        }

        if (heightSpread >= 2.25 || styleMetrics.fontSpread >= 1.65 || styleMetrics.luminanceSpread >= 0.42),
           shortTextRatio >= 0.25 {
            return .mixed
        }

        if blocks.count >= 5 && longTextRatio >= 0.45 {
            return .article
        }

        return .paragraph
    }
}

private struct TextLayoutGroup {
    private(set) var blocks: [TextBlock]
    private(set) var boundingBox: CGRect

    init(_ block: TextBlock) {
        blocks = [block]
        boundingBox = block.boundingBox
    }

    var textBlock: TextBlock {
        let sortedBlocks = blocks.sorted { lhs, rhs in
            if abs(lhs.boundingBox.minY - rhs.boundingBox.minY) > 8 {
                return lhs.boundingBox.minY < rhs.boundingBox.minY
            }
            return lhs.boundingBox.minX < rhs.boundingBox.minX
        }
        return TextBlock(
            text: sortedBlocks.map(\.text).joined(separator: " "),
            boundingBox: boundingBox,
            detectedLanguage: sortedBlocks.first(where: { $0.detectedLanguage != "und" })?.detectedLanguage ?? "und",
            visualStyle: representativeStyle
        )
    }

    mutating func append(_ block: TextBlock) {
        blocks.append(block)
        boundingBox = boundingBox.union(block.boundingBox)
    }

    func canAccept(_ block: TextBlock, layoutKind: TextLayoutKind) -> Bool {
        guard !isStandaloneUppercaseLabel else { return false }
        guard representativeStyle.isCompatible(with: block.visualStyle, strict: layoutKind == .mixed) else {
            return false
        }

        let groupHeight = max(1, medianHeight)
        let blockHeight = max(1, block.boundingBox.height)
        let heightRatio = min(groupHeight, blockHeight) / max(groupHeight, blockHeight)
        let minimumHeightRatio: CGFloat = layoutKind == .article ? 0.62 : 0.68
        guard heightRatio >= minimumHeightRatio else { return false }

        let verticalGap = block.boundingBox.minY - boundingBox.maxY
        let gapMultiplier: CGFloat
        switch layoutKind {
        case .article:
            gapMultiplier = 1.2
        case .mixed:
            gapMultiplier = 0.75
        default:
            gapMultiplier = 0.9
        }
        let maxGap = max(10, min(groupHeight, blockHeight) * gapMultiplier)
        guard verticalGap >= -groupHeight * 0.25 && verticalGap <= maxGap else { return false }

        let overlap = horizontalOverlap(with: block.boundingBox)
        let minWidth = max(1, min(boundingBox.width, block.boundingBox.width))
        let widthRatio = minWidth / max(1, max(boundingBox.width, block.boundingBox.width))
        let leftAligned = abs(block.boundingBox.minX - boundingBox.minX) <= max(14, groupHeight * 0.75)
        let centerAligned = abs(block.boundingBox.midX - boundingBox.midX) <= max(16, boundingBox.width * 0.12)
        let strongOverlap = overlap / minWidth >= 0.66 && widthRatio >= 0.55
        let shortTailLine = leftAligned
            && widthRatio >= (layoutKind == .mixed ? 0.12 : 0.03)
            && (block.text.looksLikeSentenceFragment || block.text.endsSentence)
        return (strongOverlap && (leftAligned || centerAligned || widthRatio >= 0.72))
            || shortTailLine
            || (leftAligned && widthRatio >= 0.45)
            || (centerAligned && widthRatio >= 0.65)
    }

    private var medianHeight: CGFloat {
        let heights = blocks.map { $0.boundingBox.height }.sorted()
        return heights[heights.count / 2]
    }

    private var isStandaloneUppercaseLabel: Bool {
        blocks.count == 1 && blocks[0].text.isUppercaseLabel
    }

    private var representativeStyle: TextBlockVisualStyle {
        blocks.first(where: { $0.visualStyle.hasReliableSignal })?.visualStyle ?? .unknown
    }

    private func horizontalOverlap(with rect: CGRect) -> CGFloat {
        max(0, min(boundingBox.maxX, rect.maxX) - max(boundingBox.minX, rect.minX))
    }
}

private struct VisualStyleMetrics {
    let fontSpread: CGFloat
    let luminanceSpread: CGFloat

    init(blocks: [TextBlock]) {
        let fontSizes = blocks
            .map(\.visualStyle.estimatedFontSize)
            .filter { $0 > 0 }
            .sorted()
        if let minFont = fontSizes.first, let maxFont = fontSizes.last {
            fontSpread = maxFont / max(1, minFont)
        } else {
            fontSpread = 1
        }

        let luminanceValues = blocks
            .map(\.visualStyle.foregroundLuminance)
            .filter { $0 >= 0 }
            .sorted()
        if let minLuminance = luminanceValues.first, let maxLuminance = luminanceValues.last {
            luminanceSpread = maxLuminance - minLuminance
        } else {
            luminanceSpread = 0
        }
    }
}

private extension Array {
    func adjacentPairs() -> [(Element, Element)] {
        guard count > 1 else { return [] }
        return zip(self, dropFirst()).map { ($0, $1) }
    }
}

private extension TextBlock {
    func trimmingText() -> TextBlock {
        let normalizedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .removingLeadingIconNoise()
        return TextBlock(
            text: normalizedText,
            boundingBox: boundingBox,
            detectedLanguage: detectedLanguage,
            visualStyle: visualStyle
        )
    }

    var isLikelyIconBlock: Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if trimmed.isIconGlyphOnly { return true }

        let rect = boundingBox
        let squareLike = rect.width <= rect.height * 1.8 && rect.height <= rect.width * 1.8
        let lowConfidence = visualStyle.confidence > 0 && visualStyle.confidence < 0.48
        let tiny = max(rect.width, rect.height) <= max(18, visualStyle.estimatedFontSize * 1.4)

        if trimmed.count <= 2, squareLike, tiny, lowConfidence {
            return true
        }

        return false
    }
}

private extension String {
    var trimmedCount: Int {
        trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var isMostlyPunctuation: Bool {
        let scalars = unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty else { return true }
        let lettersAndNumbers = scalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
        }
        return Double(lettersAndNumbers.count) / Double(scalars.count) < 0.35
    }

    var isUppercaseLabel: Bool {
        let letters = unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty, count <= 24 else { return false }
        let uppercase = letters.filter { CharacterSet.uppercaseLetters.contains($0) }
        return Double(uppercase.count) / Double(letters.count) > 0.8
    }

    var looksLikeSentenceFragment: Bool {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 8 else { return false }
        if text.range(of: #"[，。！？；：,.!?;:]$"#, options: .regularExpression) != nil {
            return true
        }
        if text.range(of: #"[，。！？；：,.!?;:]"#, options: .regularExpression) != nil,
           text.count >= 12 {
            return true
        }
        if let first = text.unicodeScalars.first,
           CharacterSet.lowercaseLetters.contains(first) {
            return true
        }
        return text.count >= 24
    }

    var endsSentence: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines)
            .range(of: #"[。！？.!?]$"#, options: .regularExpression) != nil
    }

    var isIconGlyphOnly: Bool {
        let scalars = unicodeScalars.filter { !$0.properties.isWhitespace }
        guard !scalars.isEmpty, scalars.count <= 3 else { return false }
        let textScalars = scalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
                || (0x3040...0x30FF).contains(Int($0.value))
                || (0xAC00...0xD7AF).contains(Int($0.value))
        }
        return textScalars.isEmpty
    }

    func removingLeadingIconNoise() -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstSpace = trimmed.firstIndex(where: { $0.isWhitespace }) else {
            return trimmed
        }

        let prefix = String(trimmed[..<firstSpace]).trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = String(trimmed[firstSpace...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty,
              !suffix.isEmpty,
              suffix.looksLikeReadableLabel,
              prefix.looksLikeIconNoisePrefix else {
            return trimmed
        }
        return suffix
    }

    var looksLikeIconNoisePrefix: Bool {
        let text = trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        if text == "..." || text == "…" || text == ".." { return true }
        if text.count == 1 {
            if let scalar = text.unicodeScalars.first {
                if CharacterSet.decimalDigits.contains(scalar) { return true }
                if CharacterSet.uppercaseLetters.contains(scalar) { return true }
                if ["本", "巴", "凸", "口", "□", "▢", "▣", "○", "●"].contains(text) { return true }
            }
        }
        return isIconGlyphOnly
    }

    var looksLikeReadableLabel: Bool {
        let scalars = unicodeScalars.filter { !$0.properties.isWhitespace }
        guard scalars.count >= 2 else { return false }
        return scalars.contains {
            CharacterSet.letters.contains($0)
                || (0x4E00...0x9FFF).contains(Int($0.value))
                || (0x3040...0x30FF).contains(Int($0.value))
                || (0xAC00...0xD7AF).contains(Int($0.value))
        }
    }
}
