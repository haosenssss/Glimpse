import Foundation
import Testing
@testable import GlimpseCore

@Suite struct ChatRequestBuilderTests {
    func makeConfig(base: String = "https://api.example.com/v1", prompt: String = "Be brief.") throws -> ChatConfig {
        try ChatConfig.make(baseURL: base, apiKey: "sk-test", model: "gpt-4o", systemPrompt: prompt, timeout: 45)
    }

    func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func targetsChatCompletionsEndpoint() throws {
        let request = ChatRequestBuilder.makeRequest(config: try makeConfig(), imageBase64: "AAA")
        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
        #expect(request.httpMethod == "POST")
    }

    @Test func trailingSlashInBaseURLIsHandled() throws {
        let request = ChatRequestBuilder.makeRequest(config: try makeConfig(base: "https://api.example.com/v1/"), imageBase64: "AAA")
        #expect(request.url?.absoluteString == "https://api.example.com/v1/chat/completions")
    }

    @Test func setsAuthAndStreamingHeaders() throws {
        let request = ChatRequestBuilder.makeRequest(config: try makeConfig(), imageBase64: "AAA")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        #expect(request.timeoutInterval == 45)
    }

    @Test func bodyContainsSystemPromptAndImage() throws {
        let body = try jsonBody(ChatRequestBuilder.makeRequest(config: try makeConfig(), imageBase64: "AAA"))
        #expect(body["model"] as? String == "gpt-4o")
        #expect(body["stream"] as? Bool == true)

        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 2)
        #expect(messages[0]["role"] as? String == "system")
        #expect(messages[0]["content"] as? String == "Be brief.")

        #expect(messages[1]["role"] as? String == "user")
        let parts = try #require(messages[1]["content"] as? [[String: Any]])
        #expect(parts.first?["type"] as? String == "image_url")
        let imageURL = try #require(parts.first?["image_url"] as? [String: Any])
        #expect(imageURL["url"] as? String == "data:image/jpeg;base64,AAA")
    }

    @Test func blankSystemPromptIsOmitted() throws {
        let body = try jsonBody(ChatRequestBuilder.makeRequest(config: try makeConfig(prompt: "  \n"), imageBase64: "AAA"))
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.count == 1)
        #expect(messages[0]["role"] as? String == "user")
    }

    @Test func configRequiresAPIKey() {
        #expect(throws: ChatError.missingAPIKey) {
            try ChatConfig.make(baseURL: "https://a.com/v1", apiKey: " ", model: "m", systemPrompt: "", timeout: 60)
        }
    }

    @Test func configRequiresModel() {
        #expect(throws: ChatError.missingModel) {
            try ChatConfig.make(baseURL: "https://a.com/v1", apiKey: "k", model: "", systemPrompt: "", timeout: 60)
        }
    }

    @Test func configRejectsInsecureRemoteURL() {
        #expect(throws: ChatError.insecureBaseURL) {
            try ChatConfig.make(baseURL: "http://a.com/v1", apiKey: "k", model: "m", systemPrompt: "", timeout: 60)
        }
    }

    @Test func modelsRequestUsesModelsEndpoint() throws {
        let request = ChatRequestBuilder.makeModelsRequest(baseURL: URL(string: "https://a.com/v1")!, apiKey: "k")
        #expect(request.url?.absoluteString == "https://a.com/v1/models")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer k")
        #expect(request.httpMethod == "GET")
    }
}
