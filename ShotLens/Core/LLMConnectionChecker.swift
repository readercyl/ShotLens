import Foundation

enum ConnectionCheckResult: Equatable {
    case available
    case unavailable
    case transientFailure
}

struct ConnectionCheckReport: Equatable {
    let result: ConnectionCheckResult
    let failureKind: PipelineFailureKind?
}

struct LLMConnectionChecker {
    let settings: TranslationSettings

    func isAvailable() async -> Bool {
        await checkAvailability() == .available
    }

    func checkAvailability() async -> ConnectionCheckResult {
        await checkReport().result
    }

    func checkReport() async -> ConnectionCheckReport {
        guard settings.isLLMConfigured else {
            return ConnectionCheckReport(result: .unavailable, failureKind: .apiNotConfigured)
        }

        do {
            try await LLMTranslator(settings: settings)
                .validateConnectivity(from: "en", to: "zh-Hans")
            return ConnectionCheckReport(result: .available, failureKind: nil)
        } catch {
            ShotLensLogger.event(
                "api_connection_test_failed",
                level: .warning,
                stage: "connection_test",
                outcome: "failed",
                error: error
            )
            return ConnectionCheckReport(result: classify(error), failureKind: failureKind(for: error))
        }
    }

    private func classify(_ error: Error) -> ConnectionCheckResult {
        if let translationError = error as? TranslationError {
            switch translationError {
            case .llmHTTPError(let statusCode):
                if statusCode == 401 || statusCode == 403 || statusCode == 404 {
                    return .unavailable
                }
                if statusCode == 408 || statusCode == 409 || statusCode == 425 || statusCode == 429 || statusCode >= 500 {
                    return .transientFailure
                }
                return .unavailable
            case .invalidLLMEndpoint, .llmNotConfigured:
                return .unavailable
            case .invalidLLMResponse, .missingSourceLanguage, .llmResponseCountMismatch:
                return .unavailable
            }
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return .transientFailure
        }
        return .unavailable
    }

    private func failureKind(for error: Error) -> PipelineFailureKind {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                return .networkTimedOut
            case .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .dnsLookupFailed:
                return .networkDisconnected
            default:
                return .networkDisconnected
            }
        }
        if let translationError = error as? TranslationError {
            switch translationError {
            case .llmHTTPError(let statusCode) where statusCode == 401 || statusCode == 403:
                return .authenticationFailed
            case .llmHTTPError(let statusCode) where statusCode == 404:
                return .endpointOrModelNotFound
            case .llmHTTPError(let statusCode) where statusCode == 400 || statusCode == 422:
                return .requestRejected
            case .llmHTTPError(let statusCode) where statusCode == 408:
                return .networkTimedOut
            case .llmHTTPError(let statusCode) where statusCode == 429:
                return .rateLimited
            case .llmHTTPError(let statusCode) where statusCode >= 500:
                return .serviceUnavailable
            case .invalidLLMEndpoint:
                return .invalidEndpoint
            case .llmNotConfigured:
                return .apiNotConfigured
            case .invalidLLMResponse, .llmResponseCountMismatch, .missingSourceLanguage, .llmHTTPError:
                return .invalidResponse
            }
        }
        return .unknownTranslation
    }
}
