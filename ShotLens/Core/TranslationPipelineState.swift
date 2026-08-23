import Foundation

enum TranslationScenario: String, Sendable {
    case word
    case smallScattered = "small_scattered"
    case largeRegion = "large_region"

    static func classify(sourceTexts: [String]) -> TranslationScenario {
        let normalized = sourceTexts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return .smallScattered }

        if normalized.count == 1 {
            let value = normalized[0]
            let wordCount = value.split(whereSeparator: { $0.isWhitespace }).count
            if wordCount == 1, value.count <= 48 {
                return .word
            }
        }

        let totalCharacters = normalized.reduce(0) { $0 + $1.count }
        if normalized.count <= 8, totalCharacters <= 600 {
            return .smallScattered
        }
        return .largeRegion
    }
}

enum PipelineRecoveryAction: Equatable, Sendable {
    case retryCapture
    case retryOCR
    case reselect
    case retryTranslation
    case openSettings
    case none
}

enum PipelineFailureKind: String, Sendable {
    case captureFailed = "capture_failed"
    case cropFailed = "crop_failed"
    case ocrHelperMissing = "ocr_helper_missing"
    case ocrTimedOut = "ocr_timed_out"
    case ocrFailed = "ocr_failed"
    case noText = "no_text"
    case noForeignText = "no_foreign_text"
    case networkTimedOut = "network_timed_out"
    case networkDisconnected = "network_disconnected"
    case authenticationFailed = "authentication_failed"
    case endpointOrModelNotFound = "endpoint_or_model_not_found"
    case requestRejected = "request_rejected"
    case rateLimited = "rate_limited"
    case serviceUnavailable = "service_unavailable"
    case invalidResponse = "invalid_response"
    case apiNotConfigured = "api_not_configured"
    case invalidEndpoint = "invalid_endpoint"
    case partialTranslation = "partial_translation"
    case unknownTranslation = "unknown_translation"
}

struct PipelineFailurePresentation: Equatable, Sendable {
    let kind: PipelineFailureKind
    let title: String
    let detail: String
    let actionTitle: String?
    let recovery: PipelineRecoveryAction

    static func make(
        kind: PipelineFailureKind,
        completedCount: Int = 0,
        totalCount: Int = 0
    ) -> PipelineFailurePresentation {
        switch kind {
        case .captureFailed:
            return .init(kind: kind, title: "无法截取屏幕", detail: "系统没有返回可用截图。", actionTitle: "重试截图", recovery: .retryCapture)
        case .cropFailed:
            return .init(kind: kind, title: "无法处理框选内容", detail: "截图裁剪失败，请重新截图。", actionTitle: "重试截图", recovery: .retryCapture)
        case .ocrHelperMissing:
            return .init(kind: kind, title: "识别组件不可用", detail: "OCR 组件不存在或无法启动。", actionTitle: "重新识别", recovery: .retryOCR)
        case .ocrTimedOut:
            return .init(kind: kind, title: "文字识别超时", detail: "截图仍然保留，可以再次识别。", actionTitle: "重新识别", recovery: .retryOCR)
        case .ocrFailed:
            return .init(kind: kind, title: "文字识别失败", detail: "识别组件没有返回有效结果。", actionTitle: "重新识别", recovery: .retryOCR)
        case .noText:
            return .init(kind: kind, title: "没有识别到文字", detail: "可以扩大框选范围后再试。", actionTitle: "重新框选", recovery: .reselect)
        case .noForeignText:
            return .init(kind: kind, title: "没有需要翻译的内容", detail: "框选内容可能已经是中文。", actionTitle: "重新框选", recovery: .reselect)
        case .networkTimedOut:
            return .init(kind: kind, title: "翻译连接超时", detail: "OCR 结果已经保留，可以直接重试。", actionTitle: "重试翻译", recovery: .retryTranslation)
        case .networkDisconnected:
            return .init(kind: kind, title: "网络连接中断", detail: "OCR 结果已经保留，联网后可以重试。", actionTitle: "重试翻译", recovery: .retryTranslation)
        case .authenticationFailed:
            return .init(kind: kind, title: "API 验证失败", detail: "请检查 Key 或服务权限。", actionTitle: "打开设置", recovery: .openSettings)
        case .endpointOrModelNotFound:
            return .init(kind: kind, title: "接口或模型不存在", detail: "请检查 API 地址和模型名称。", actionTitle: "打开设置", recovery: .openSettings)
        case .requestRejected:
            return .init(kind: kind, title: "翻译请求被拒绝", detail: "请检查模型名称或服务参数。", actionTitle: "打开设置", recovery: .openSettings)
        case .rateLimited:
            return .init(kind: kind, title: "API 请求过多", detail: "服务暂时限流，请稍后重试。", actionTitle: "重试翻译", recovery: .retryTranslation)
        case .serviceUnavailable:
            return .init(kind: kind, title: "翻译服务异常", detail: "OCR 结果已经保留，可以稍后重试。", actionTitle: "重试翻译", recovery: .retryTranslation)
        case .invalidResponse:
            return .init(kind: kind, title: "翻译返回无效", detail: "模型返回内容无法可靠对应原文。", actionTitle: "重试翻译", recovery: .retryTranslation)
        case .apiNotConfigured:
            return .init(kind: kind, title: "尚未配置 API", detail: "请先填写 API 地址和 Key。", actionTitle: "打开设置", recovery: .openSettings)
        case .invalidEndpoint:
            return .init(kind: kind, title: "API 地址无效", detail: "请检查地址格式后再试。", actionTitle: "打开设置", recovery: .openSettings)
        case .partialTranslation:
            let safeTotal = max(totalCount, completedCount)
            return .init(
                kind: kind,
                title: "已完成 \(completedCount)/\(safeTotal)",
                detail: "未完成内容保留原文，可以只重试缺失项。",
                actionTitle: "重试未完成项",
                recovery: .retryTranslation
            )
        case .unknownTranslation:
            return .init(kind: kind, title: "翻译失败", detail: "OCR 结果已经保留，可以再次翻译。", actionTitle: "重试翻译", recovery: .retryTranslation)
        }
    }
}

struct PipelineAttemptGate: Sendable {
    private(set) var activeID: UUID?

    var isRunning: Bool { activeID != nil }

    mutating func begin() -> UUID? {
        guard activeID == nil else { return nil }
        let id = UUID()
        activeID = id
        return id
    }

    mutating func finish(_ id: UUID) {
        guard activeID == id else { return }
        activeID = nil
    }

    mutating func cancel() {
        activeID = nil
    }
}
