import Foundation

public enum ChatError: Error, Equatable, Sendable {
    case invalidBaseURL
    case insecureBaseURL
    case missingAPIKey
    case missingModel
    case http(status: Int, message: String?)
    case server(String)
    case timeout(seconds: Int)
    case emptyAnswer
    case invalidResponse
    case network(String)
    case capture(String)

    /// One line, short enough for a menu item.
    public var shortDescription: String {
        switch self {
        case .invalidBaseURL: return "Invalid base URL"
        case .insecureBaseURL: return "Base URL must use https"
        case .missingAPIKey: return "API key not set"
        case .missingModel: return "Model not set"
        case .http(let status, let message):
            return "\(status) \(message ?? HTTPURLResponse.localizedString(forStatusCode: status))"
        case .server(let message): return message
        case .timeout(let seconds): return "Timeout (\(seconds)s)"
        case .emptyAnswer: return "Empty answer"
        case .invalidResponse: return "Unexpected response from server"
        case .network(let message): return message
        case .capture(let message): return message
        }
    }

    public static func wrap(_ error: Error) -> ChatError {
        if let chatError = error as? ChatError { return chatError }
        if let urlError = error as? URLError { return .network(describe(urlError)) }
        return .network(error.localizedDescription)
    }

    private static func describe(_ error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet: return "No internet connection"
        case .timedOut: return "Network timed out"
        case .cannotFindHost, .dnsLookupFailed: return "Cannot find host"
        case .cannotConnectToHost: return "Cannot connect to host"
        case .secureConnectionFailed, .serverCertificateUntrusted: return "TLS connection failed"
        default: return error.localizedDescription
        }
    }
}

extension ChatError: LocalizedError {
    public var errorDescription: String? { shortDescription }
}
