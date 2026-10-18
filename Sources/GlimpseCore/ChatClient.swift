import Foundation

public struct ModelInfo: Equatable, Sendable {
    public let id: String
    /// From the server's metadata when it says (OpenRouter does); `nil` when unknown.
    public let acceptsImages: Bool?

    public init(id: String, acceptsImages: Bool?) {
        self.id = id
        self.acceptsImages = acceptsImages
    }
}

public struct ChatClient: Sendable {
    let session: URLSession

    public init(session: URLSession = ChatClient.makeEphemeralSession()) {
        self.session = session
    }

    /// No disk cache, no cookies, no credential storage: nothing about a request outlives it.
    public static func makeEphemeralSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: configuration)
    }

    public func streamAnswer(request: URLRequest) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await stream(request: request, into: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: ChatError.wrap(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Like `listModels`, but if the base URL 404s and lacks a trailing `/v1`, retries with it —
    /// the most common base-URL mistake. Returns the URL that worked.
    public func discoverModels(baseURL: URL, apiKey: String) async throws -> (baseURL: URL, models: [ModelInfo]) {
        do {
            return (baseURL, try await listModels(baseURL: baseURL, apiKey: apiKey))
        } catch ChatError.http(status: 404, let message) where baseURL.lastPathComponent != "v1" {
            let candidate = baseURL.appendingPathComponent("v1")
            guard let models = try? await listModels(baseURL: candidate, apiKey: apiKey) else {
                throw ChatError.http(status: 404, message: message)
            }
            return (candidate, models)
        }
    }

    public func listModels(baseURL: URL, apiKey: String) async throws -> [ModelInfo] {
        let request = ChatRequestBuilder.makeModelsRequest(baseURL: baseURL, apiKey: apiKey)
        do {
            let (data, response) = try await session.data(for: request)
            try Self.checkStatus(response, body: data)
            guard let list = try? JSONDecoder().decode(ModelList.self, from: data) else {
                throw ChatError.invalidResponse
            }
            return list.data
                .map { ModelInfo(id: $0.id, acceptsImages: $0.architecture?.inputModalities.map { $0.contains("image") }) }
                .sorted { $0.id < $1.id }
        } catch {
            throw ChatError.wrap(error)
        }
    }

    private func stream(
        request: URLRequest, into continuation: AsyncThrowingStream<ChatEvent, Error>.Continuation
    ) async throws {
        let (bytes, response) = try await session.bytes(for: request)

        if !Self.isSuccess(response) {
            try Self.checkStatus(response, body: try await Self.collect(bytes))
        }

        if Self.isJSON(response) {
            continuation.yield(.content(try SSEParser.parseCompletion(data: try await Self.collect(bytes))))
            continuation.yield(.done)
            return
        }

        for try await line in bytes.lines {
            for event in try SSEParser.parse(line: line) {
                continuation.yield(event)
                if event == .done { return }
            }
        }
    }

    private static func collect(_ bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes { data.append(byte) }
        return data
    }

    private static func isSuccess(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse else { return false }
        return (200..<300).contains(http.statusCode)
    }

    private static func isJSON(_ response: URLResponse) -> Bool {
        let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? ""
        return type.lowercased().contains("application/json")
    }

    private static func checkStatus(_ response: URLResponse, body: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw ChatError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw ChatError.http(status: http.statusCode, message: SSEParser.errorMessage(from: body))
        }
    }
}

private struct ModelList: Decodable {
    struct Model: Decodable {
        let id: String
        let architecture: Architecture?
    }

    struct Architecture: Decodable {
        let inputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case inputModalities = "input_modalities"
        }
    }

    let data: [Model]
}
