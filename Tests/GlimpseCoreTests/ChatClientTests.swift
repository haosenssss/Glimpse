import Foundation
import Testing
@testable import GlimpseCore

/// Serves canned responses keyed by request host so parallel tests don't collide.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let status: Int
        let contentType: String
        let body: Data
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var stubs: [String: Stub] = [:]

    /// `path` narrows the stub to one URL path; without it the stub answers any path on the host.
    static func register(host: String, path: String? = nil, status: Int, contentType: String, body: String) {
        let key = path.map { "\(host)\($0)" } ?? host
        lock.withLock { stubs[key] = Stub(status: status, contentType: contentType, body: Data(body.utf8)) }
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        guard let stub = Self.lock.withLock({ Self.stubs[host + path] ?? Self.stubs[host] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": stub.contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite struct ChatClientTests {
    func request(host: String) throws -> URLRequest {
        let config = try ChatConfig.make(baseURL: "https://\(host)/v1", apiKey: "k", model: "m", systemPrompt: "p", timeout: 10)
        return ChatRequestBuilder.makeRequest(config: config, imageBase64: "AAA")
    }

    func collect(_ stream: AsyncThrowingStream<ChatEvent, Error>) async throws -> [ChatEvent] {
        var events: [ChatEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    @Test func streamsServerSentEvents() async throws {
        let body = """
        data: {"choices":[{"delta":{"reasoning_content":"r"}}]}

        data: {"choices":[{"delta":{"content":"B"}}]}

        data: [DONE]

        """
        StubURLProtocol.register(host: "stream.test", status: 200, contentType: "text/event-stream", body: body)
        let client = ChatClient(session: StubURLProtocol.session())

        let events = try await collect(client.streamAnswer(request: try request(host: "stream.test")))
        #expect(events == [.reasoning("r"), .content("B"), .done])
    }

    @Test func httpErrorsCarryServerMessage() async throws {
        StubURLProtocol.register(host: "auth.test", status: 401, contentType: "application/json", body: #"{"error":{"message":"Invalid API key"}}"#)
        let client = ChatClient(session: StubURLProtocol.session())

        await #expect(throws: ChatError.http(status: 401, message: "Invalid API key")) {
            _ = try await collect(client.streamAnswer(request: try request(host: "auth.test")))
        }
    }

    @Test func fallsBackToNonStreamingJSON() async throws {
        StubURLProtocol.register(host: "json.test", status: 200, contentType: "application/json", body: #"{"choices":[{"message":{"content":"C"}}]}"#)
        let client = ChatClient(session: StubURLProtocol.session())

        let events = try await collect(client.streamAnswer(request: try request(host: "json.test")))
        #expect(events == [.content("C"), .done])
    }

    @Test func listsModelsSorted() async throws {
        StubURLProtocol.register(host: "models.test", status: 200, contentType: "application/json", body: #"{"data":[{"id":"zeta"},{"id":"alpha"}]}"#)
        let client = ChatClient(session: StubURLProtocol.session())

        let models = try await client.listModels(baseURL: URL(string: "https://models.test/v1")!, apiKey: "k")
        #expect(models == [ModelInfo(id: "alpha", acceptsImages: nil), ModelInfo(id: "zeta", acceptsImages: nil)])
    }

    @Test func readsImageSupportFromOpenRouterStyleMetadata() async throws {
        let body = #"{"data":[{"id":"a/vision","architecture":{"input_modalities":["text","image"]}},{"id":"b/text","architecture":{"input_modalities":["text"]}}]}"#
        StubURLProtocol.register(host: "modalities.test", status: 200, contentType: "application/json", body: body)
        let client = ChatClient(session: StubURLProtocol.session())

        let models = try await client.listModels(baseURL: URL(string: "https://modalities.test/api/v1")!, apiKey: "k")
        #expect(models == [ModelInfo(id: "a/vision", acceptsImages: true), ModelInfo(id: "b/text", acceptsImages: false)])
    }

    @Test func discoveryAppendsMissingV1After404() async throws {
        StubURLProtocol.register(host: "discover.test", path: "/api/models", status: 404, contentType: "text/html", body: "<html>404</html>")
        StubURLProtocol.register(host: "discover.test", path: "/api/v1/models", status: 200, contentType: "application/json", body: #"{"data":[{"id":"m"}]}"#)
        let client = ChatClient(session: StubURLProtocol.session())

        let result = try await client.discoverModels(baseURL: URL(string: "https://discover.test/api")!, apiKey: "k")
        #expect(result.baseURL.absoluteString == "https://discover.test/api/v1")
        #expect(result.models.map(\.id) == ["m"])
    }

    @Test func discoveryKeepsWorkingBaseURL() async throws {
        StubURLProtocol.register(host: "discover-ok.test", path: "/v1/models", status: 200, contentType: "application/json", body: #"{"data":[{"id":"m"}]}"#)
        let client = ChatClient(session: StubURLProtocol.session())

        let result = try await client.discoverModels(baseURL: URL(string: "https://discover-ok.test/v1")!, apiKey: "k")
        #expect(result.baseURL.absoluteString == "https://discover-ok.test/v1")
    }

    @Test func discoveryReportsOriginalErrorWhenRetryAlsoFails() async throws {
        StubURLProtocol.register(host: "discover-fail.test", status: 404, contentType: "text/plain", body: "nope")
        let client = ChatClient(session: StubURLProtocol.session())

        await #expect(throws: ChatError.http(status: 404, message: "nope")) {
            _ = try await client.discoverModels(baseURL: URL(string: "https://discover-fail.test/api")!, apiKey: "k")
        }
    }

    @Test func modelListErrorsAreReported() async throws {
        StubURLProtocol.register(host: "models-fail.test", status: 404, contentType: "text/plain", body: "not found")
        let client = ChatClient(session: StubURLProtocol.session())

        await #expect(throws: ChatError.http(status: 404, message: "not found")) {
            _ = try await client.listModels(baseURL: URL(string: "https://models-fail.test/v1")!, apiKey: "k")
        }
    }
}
