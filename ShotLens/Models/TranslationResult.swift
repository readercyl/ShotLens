import CoreGraphics

/// OCR 文本块的视觉特征，用来辅助判断同一语义段落。
struct TextBlockVisualStyle: Codable, Equatable {
    let confidence: Float
    let estimatedFontSize: CGFloat
    let foregroundRed: CGFloat
    let foregroundGreen: CGFloat
    let foregroundBlue: CGFloat
    let foregroundLuminance: CGFloat
    let strokeDensity: CGFloat

    static let unknown = TextBlockVisualStyle(
        confidence: 0,
        estimatedFontSize: 0,
        foregroundRed: 0,
        foregroundGreen: 0,
        foregroundBlue: 0,
        foregroundLuminance: -1,
        strokeDensity: 0
    )

    var hasReliableSignal: Bool {
        confidence > 0 || estimatedFontSize > 0 || foregroundLuminance >= 0 || strokeDensity > 0
    }

    func isCompatible(with other: TextBlockVisualStyle, strict: Bool) -> Bool {
        guard hasReliableSignal, other.hasReliableSignal else { return true }

        if estimatedFontSize > 0, other.estimatedFontSize > 0 {
            let ratio = min(estimatedFontSize, other.estimatedFontSize) / max(estimatedFontSize, other.estimatedFontSize)
            let minimumRatio: CGFloat = strict ? 0.76 : 0.62
            guard ratio >= minimumRatio else { return false }
        }

        if foregroundLuminance >= 0, other.foregroundLuminance >= 0 {
            let tolerance: CGFloat = strict ? 0.22 : 0.34
            guard abs(foregroundLuminance - other.foregroundLuminance) <= tolerance else { return false }
        }

        if strokeDensity > 0, other.strokeDensity > 0 {
            let ratio = min(strokeDensity, other.strokeDensity) / max(strokeDensity, other.strokeDensity)
            let minimumRatio: CGFloat = strict ? 0.42 : 0.28
            guard ratio >= minimumRatio else { return false }
        }

        return true
    }
}

struct TextRun: Equatable {
    let text: String
    let boundingBox: CGRect
}

/// OCR 识别出的单个文本行或语义块
struct TextBlock {
    /// 识别出的原文
    let text: String
    /// 文本块在截图中的像素坐标（原点左上角）
    let boundingBox: CGRect
    /// 检测到的语言代码，如 "zh-Hans"、"en"
    let detectedLanguage: String
    /// OCR 估算出的视觉特征
    let visualStyle: TextBlockVisualStyle
    /// 行内可翻译的英文子范围；中文和数字仅作为受保护的语义上下文。
    let englishRuns: [TextRun]

    init(
        text: String,
        boundingBox: CGRect,
        detectedLanguage: String,
        visualStyle: TextBlockVisualStyle = .unknown,
        englishRuns: [TextRun] = []
    ) {
        self.text = text
        self.boundingBox = boundingBox
        self.detectedLanguage = detectedLanguage
        self.visualStyle = visualStyle
        self.englishRuns = englishRuns
    }
}

/// 翻译后的文本块
struct TranslatedBlock {
    /// 原文块
    let original: TextBlock
    /// 译文
    let translatedText: String
}
