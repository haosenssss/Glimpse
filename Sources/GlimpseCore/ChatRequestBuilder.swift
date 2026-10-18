import Foundation

/// Everything needed to send one request, already validated.
public struct ChatConfig: Equatable, Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let model: String
    public let systemPrompt: String
    public let timeout: TimeInterval

    public static func make(
        baseURL: String, apiKey: String, model: String, systemPrompt: String, timeout: TimeInterval
    ) throws -> ChatConfig {
        let url = try BaseURLValidator.validate(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let modelName = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ChatError.missingAPIKey }
        guard !modelName.isEmpty else { throw ChatError.missingModel }
        return ChatConfig(baseURL: url, apiKey: key, model: modelName, systemPrompt: systemPrompt, timeout: timeout)
    }
}

/// Builds OpenAI-compatible `/chat/completions` and `/models` requests.
public enum ChatRequestBuilder {
    public static func makeRequest(config: ChatConfig, imageBase64: String) -> URLRequest {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.timeoutInterval = config.timeout
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try? JSONEncoder().encode(body(config: config, imageBase64: imageBase64))
        return request
    }

    public static func makeModelsRequest(baseURL: URL, apiKey: String) -> URLRequest {
        var request = URLRequest(url: baseURL.appendingPathComponent("models"))
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    static func body(config: ChatConfig, imageBase64: String) -> CompletionBody {
        let image = Message(role: "user", content: .parts([
            .init(type: "image_url", imageURL: .init(url: "data:image/jpeg;base64,\(imageBase64)")),
        ]))
        let prompt = config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let messages = prompt.isEmpty ? [image] : [Message(role: "system", content: .text(prompt)), image]
        return CompletionBody(model: config.model, stream: true, messages: messages)
    }
}

// MARK: - Wire format

struct CompletionBody: Encodable {
    let model: String
    let stream: Bool
    let messages: [Message]
}

struct Message: Encodable {
    let role: String
    let content: Content
}

enum Content: Encodable {
    case text(String)
    case parts([Part])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .parts(let parts): try container.encode(parts)
        }
    }
}

struct Part: Encodable {
    struct ImageURL: Encodable {
        let url: String
    }

    let type: String
    let imageURL: ImageURL

    enum CodingKeys: String, CodingKey {
        case type
        case imageURL = "image_url"
    }
}
