import Foundation

public enum AIServiceError: Error, Equatable, LocalizedError, Sendable {
    case missingAPIKey
    case invalidEndpoint
    case invalidResponse(String)
    case rateLimited(retryAfter: Date?)
    case modelOverloaded
    case proxyAuthRequired
    case proxySessionExpired
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "AI API key is missing."
        case .invalidEndpoint:
            return "AI endpoint is invalid."
        case .invalidResponse(let message):
            return "AI response is invalid: \(message)"
        case .rateLimited:
            return "AI service is rate limited."
        case .modelOverloaded:
            return "AI model is overloaded."
        case .proxyAuthRequired:
            return "Sign in is required for proxy AI."
        case .proxySessionExpired:
            return "Proxy session expired."
        case .network(let message):
            return "Network error: \(message)"
        }
    }
}
