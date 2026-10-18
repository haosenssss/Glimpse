import Foundation

/// Requests carry screenshots and an API key, so anything leaving the machine must
/// use https. Plain http is only allowed for local model servers.
public enum BaseURLValidator {
    static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1", "[::1]"]

    public static func validate(_ raw: String) throws -> URL {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while text.hasSuffix("/") { text.removeLast() }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty,
              let url = components.url
        else { throw ChatError.invalidBaseURL }

        switch scheme {
        case "https":
            return url
        case "http":
            guard localHosts.contains(host.lowercased()) else { throw ChatError.insecureBaseURL }
            return url
        default:
            throw ChatError.invalidBaseURL
        }
    }
}
