import Foundation

public enum ChatEvent: Equatable, Sendable {
    case reasoning(String)
    case content(String)
    case done
}

/// Parses OpenAI-style server-sent events one line at a time.
public enum SSEParser {
    static let maxErrorLength = 120

    public static func parse(line: String) throws -> [ChatEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return [.done] }

        guard let chunk = try? JSONDecoder().decode(StreamChunk.self, from: Data(payload.utf8)) else { return [] }
        if let message = chunk.error?.message { throw ChatError.server(message) }

        let delta = chunk.choices?.first?.delta
        let reasoning = (delta?.reasoningContent ?? delta?.reasoning).flatMap(nonEmpty).map(ChatEvent.reasoning)
        let content = delta?.content.flatMap(nonEmpty).map(ChatEvent.content)
        return [reasoning, content].compactMap { $0 }
    }

    /// Some servers ignore `stream: true` and answer with one JSON body.
    public static func parseCompletion(data: Data) throws -> String {
        guard let completion = try? JSONDecoder().decode(Completion.self, from: data),
              let content = completion.choices.first?.message.content
        else { throw ChatError.invalidResponse }
        return content
    }

    /// Best-effort human-readable message from an error response body.
    public static func errorMessage(from data: Data) -> String? {
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data),
           let message = body.error?.message ?? body.message {
            return message
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return text.count > maxErrorLength ? String(text.prefix(maxErrorLength)) + "…" : text
    }

    private static func nonEmpty(_ text: String) -> String? {
        text.isEmpty ? nil : text
    }
}

// MARK: - Wire format

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        let delta: Delta?
    }

    struct Delta: Decodable {
        let content: String?
        let reasoningContent: String?
        let reasoning: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
            case reasoning
        }
    }

    let choices: [Choice]?
    let error: APIError?
}

private struct Completion: Decodable {
    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }

    let choices: [Choice]
}

/// Servers send either `"error": {"message": "…"}` or `"error": "…"`.
private struct APIError: Decodable {
    let message: String?

    init(from decoder: Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            message = text
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try container.decodeIfPresent(String.self, forKey: .message)
    }

    private enum CodingKeys: String, CodingKey {
        case message
    }
}

private struct ErrorBody: Decodable {
    let error: APIError?
    let message: String?
}
