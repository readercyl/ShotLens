import Foundation

/// 只依据屏幕几何关系恢复视觉语义块，不猜测页面属于文章、菜单或卡片。
enum SemanticTextGrouper {
    static func merge(_ blocks: [TextBlock]) -> [TextBlock] {
        let readable = blocks.compactMap { block -> TextBlock? in
            let text = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.containsLetterOrNumber else { return nil }
            return TextBlock(
                text: text,
                boundingBox: block.boundingBox,
                detectedLanguage: block.detectedLanguage,
                visualStyle: block.visualStyle,
                englishRuns: block.englishRuns
            )
        }
        let rows = makeRows(from: readable)
        var groups: [FlowGroup] = []
        for row in rows {
            if let index = groups.indices.last(where: { groups[$0].canAppend(row) }) {
                groups[index].append(row)
            } else {
                groups.append(FlowGroup(row))
            }
        }
        return groups.map(\.textBlock)
    }

    private static func makeRows(from blocks: [TextBlock]) -> [TextRow] {
        let ordered = blocks.sorted(by: readingOrder)
        var rows: [TextRow] = []
        for block in ordered {
            if let index = rows.indices.last(where: { rows[$0].canAppendOnSameLine(block) }) {
                rows[index].append(block)
            } else {
                rows.append(TextRow(block))
            }
        }
        return rows.sorted { readingOrder($0.textBlock, $1.textBlock) }
    }

    private static func readingOrder(_ lhs: TextBlock, _ rhs: TextBlock) -> Bool {
        let tolerance = max(6, min(lhs.boundingBox.height, rhs.boundingBox.height) * 0.35)
        if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) > tolerance {
            return lhs.boundingBox.minY < rhs.boundingBox.minY
        }
        return lhs.boundingBox.minX < rhs.boundingBox.minX
    }
}

private struct TextRow {
    private(set) var blocks: [TextBlock]
    private(set) var boundingBox: CGRect

    init(_ block: TextBlock) {
        blocks = [block]
        boundingBox = block.boundingBox
    }

    var textBlock: TextBlock {
        let ordered = blocks.sorted { $0.boundingBox.minX < $1.boundingBox.minX }
        return TextBlock(
            text: ordered.map(\.text).joined(separator: " "),
            boundingBox: boundingBox,
            detectedLanguage: ordered.contains(where: { $0.detectedLanguage == "mixed" }) ? "mixed" : "en",
            visualStyle: ordered.first(where: { $0.visualStyle.hasReliableSignal })?.visualStyle ?? .unknown,
            englishRuns: ordered.flatMap(\.englishRuns)
        )
    }

    mutating func append(_ block: TextBlock) {
        blocks.append(block)
        boundingBox = boundingBox.union(block.boundingBox)
    }

    func canAppendOnSameLine(_ block: TextBlock) -> Bool {
        let minHeight = max(1, min(boundingBox.height, block.boundingBox.height))
        let maxHeight = max(1, max(boundingBox.height, block.boundingBox.height))
        let overlap = max(0, min(boundingBox.maxY, block.boundingBox.maxY) - max(boundingBox.minY, block.boundingBox.minY))
        let aligned = overlap / minHeight >= 0.45
            || abs(boundingBox.midY - block.boundingBox.midY) <= maxHeight * 0.35
        let horizontalGap = block.boundingBox.minX - boundingBox.maxX
        let previousText = blocks.max(by: { $0.boundingBox.maxX < $1.boundingBox.maxX })?.text ?? ""
        let continuesSentence = previousText.endsWithContinuationMarker
            || block.text.startsWithContinuationToken
        let maximumGap = continuesSentence
            ? max(18, minHeight * 1.6)
            : max(10, minHeight * 0.4)
        return aligned
            && horizontalGap >= -minHeight * 0.3
            && horizontalGap <= maximumGap
    }
}

private struct FlowGroup {
    private(set) var rows: [TextRow]
    private(set) var boundingBox: CGRect

    init(_ row: TextRow) {
        rows = [row]
        boundingBox = row.boundingBox
    }

    var textBlock: TextBlock {
        let ordered = rows.sorted { $0.boundingBox.minY < $1.boundingBox.minY }
        let blocks = ordered.map(\.textBlock)
        return TextBlock(
            text: blocks.map(\.text).joined(separator: " "),
            boundingBox: boundingBox,
            detectedLanguage: blocks.contains(where: { $0.detectedLanguage == "mixed" }) ? "mixed" : "en",
            visualStyle: blocks.first(where: { $0.visualStyle.hasReliableSignal })?.visualStyle ?? .unknown,
            englishRuns: blocks.flatMap(\.englishRuns)
        )
    }

    mutating func append(_ row: TextRow) {
        rows.append(row)
        boundingBox = boundingBox.union(row.boundingBox)
    }

    func canAppend(_ row: TextRow) -> Bool {
        guard let previous = rows.last else { return false }
        let previousBlock = previous.textBlock
        let nextBlock = row.textBlock
        let previousRect = previous.boundingBox
        let nextRect = row.boundingBox
        let minHeight = max(1, min(previousRect.height, nextRect.height))
        let maxHeight = max(1, max(previousRect.height, nextRect.height))
        let continuesSentence = nextBlock.text.startsWithLowercaseLetter
            || previousBlock.text.endsWithContinuationMarker
        let minimumHeightRatio: CGFloat = continuesSentence ? 0.45 : 0.55
        guard minHeight / maxHeight >= minimumHeightRatio else {
            return false
        }
        if !continuesSentence,
           !previousBlock.visualStyle.isCompatible(with: nextBlock.visualStyle, strict: false) {
            return false
        }

        let verticalGap = nextRect.minY - previousRect.maxY
        guard verticalGap >= -minHeight * 0.35 else { return false }

        let horizontalOverlap = max(0, min(previousRect.maxX, nextRect.maxX) - max(previousRect.minX, nextRect.minX))
        let minWidth = max(1, min(previousRect.width, nextRect.width))
        let leftAligned = abs(previousRect.minX - nextRect.minX) <= max(18, minHeight * 1.25)
        let centerAligned = abs(previousRect.midX - nextRect.midX) <= max(20, minWidth * 0.22)
        let stronglyOverlapping = horizontalOverlap / minWidth >= 0.55
        let modestIndent = nextRect.minX >= previousRect.minX
            && nextRect.minX - previousRect.minX <= minHeight * 2.2
        guard leftAligned || centerAligned || stronglyOverlapping || modestIndent else { return false }

        let baseGap = max(4, minHeight * 0.35)
        if verticalGap <= baseGap { return true }
        return continuesSentence && verticalGap <= max(10, minHeight * 0.95)
    }
}

/// 根据语义密度决定局部替换还是整块重排：孤立英文尽量原位替换，
/// 英文占主体且只夹少量中文或数字时保留受保护内容后整块重排。
struct TranslationContentPlan {
    private struct BlockPlan {
        let original: TextBlock
        let translationIndex: Int
    }

    let sourceTexts: [String]
    private let blockPlans: [BlockPlan]

    static func make(from blocks: [TextBlock]) -> TranslationContentPlan {
        var sourceTexts: [String] = []
        var blockPlans: [BlockPlan] = []
        for block in blocks where block.text.containsLatinLetter {
            let source = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let localizedBlocks = localizedEnglishBlocks(from: block)

            if shouldReflowSemanticBlock(source: source, englishRunCount: block.englishRuns.count)
                || localizedBlocks.isEmpty {
                let index = sourceTexts.count
                sourceTexts.append(source)
                blockPlans.append(BlockPlan(original: block, translationIndex: index))
                continue
            }

            for localizedBlock in localizedBlocks {
                let index = sourceTexts.count
                sourceTexts.append(localizedBlock.text)
                blockPlans.append(BlockPlan(original: localizedBlock, translationIndex: index))
            }
        }
        return TranslationContentPlan(sourceTexts: sourceTexts, blockPlans: blockPlans)
    }

    private static func shouldReflowSemanticBlock(source: String, englishRunCount: Int) -> Bool {
        let latinCount = source.latinLetterCount
        let hanCount = source.hanCharacterCount
        let digitCount = source.digitCount
        let protectedCount = hanCount + digitCount
        let semanticCount = max(1, latinCount + protectedCount)
        let protectedRatio = Double(protectedCount) / Double(semanticCount)
        let sentenceLike = englishRunCount > 3
            || source.contains(where: { ".!?。！？".contains($0) })

        if protectedCount > 0 {
            return protectedRatio <= 0.35
        }
        return sentenceLike || englishRunCount > 3
    }

    private static func localizedEnglishBlocks(from block: TextBlock) -> [TextBlock] {
        let runs = block.englishRuns.sorted {
            let tolerance = max(4, min($0.boundingBox.height, $1.boundingBox.height) * 0.35)
            if abs($0.boundingBox.midY - $1.boundingBox.midY) > tolerance {
                return $0.boundingBox.minY < $1.boundingBox.minY
            }
            return $0.boundingBox.minX < $1.boundingBox.minX
        }
        guard !runs.isEmpty else { return [] }

        var groups: [[TextRun]] = []
        for run in runs {
            if let lastGroup = groups.last,
               let previous = lastGroup.last,
               canJoinLocalizedRuns(previous, run) {
                groups[groups.count - 1].append(run)
            } else {
                groups.append([run])
            }
        }

        return groups.map { group in
            let boundingBox = group.dropFirst().reduce(group[0].boundingBox) {
                $0.union($1.boundingBox)
            }
            return TextBlock(
                text: group.map(\.text).joined(separator: " "),
                boundingBox: boundingBox,
                detectedLanguage: "en",
                visualStyle: block.visualStyle,
                englishRuns: group
            )
        }
    }

    private static func canJoinLocalizedRuns(_ lhs: TextRun, _ rhs: TextRun) -> Bool {
        let minHeight = max(1, min(lhs.boundingBox.height, rhs.boundingBox.height))
        let verticalDistance = abs(lhs.boundingBox.midY - rhs.boundingBox.midY)
        let horizontalGap = rhs.boundingBox.minX - lhs.boundingBox.maxX
        return verticalDistance <= minHeight * 0.4
            && horizontalGap >= -minHeight * 0.25
            && horizontalGap <= max(8, minHeight * 0.75)
    }

    func applying(_ translations: [String]) -> [TranslatedBlock]? {
        applyingAvailable(translations.map(Optional.some))
    }

    func applyingAvailable(_ translations: [String?]) -> [TranslatedBlock]? {
        guard translations.count == sourceTexts.count else { return nil }
        return blockPlans.compactMap { plan in
            guard let translation = translations[plan.translationIndex] else { return nil }
            return TranslatedBlock(original: plan.original, translatedText: translation)
        }
    }
}

private extension String {
    var containsLetterOrNumber: Bool {
        unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
    }

    var containsLatinLetter: Bool {
        unicodeScalars.contains { scalar in
            (65...90).contains(Int(scalar.value))
                || (97...122).contains(Int(scalar.value))
                || (0x00C0...0x024F).contains(Int(scalar.value))
        }
    }

    var latinLetterCount: Int {
        unicodeScalars.filter { scalar in
            (65...90).contains(Int(scalar.value))
                || (97...122).contains(Int(scalar.value))
                || (0x00C0...0x024F).contains(Int(scalar.value))
        }.count
    }

    var hanCharacterCount: Int {
        unicodeScalars.filter { scalar in
            (0x3400...0x4DBF).contains(Int(scalar.value))
                || (0x4E00...0x9FFF).contains(Int(scalar.value))
                || (0xF900...0xFAFF).contains(Int(scalar.value))
        }.count
    }

    var digitCount: Int {
        unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }.count
    }

    var startsWithLowercaseLetter: Bool {
        first(where: \.isLetter)?.isLowercase == true
    }

    var startsWithContinuationToken: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return false }
        return first.isLowercase || first.isNumber || "#),.;:!?%".contains(first)
    }

    var endsWithContinuationMarker: Bool {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return ",;:/–—-(&".contains(last)
    }
}
