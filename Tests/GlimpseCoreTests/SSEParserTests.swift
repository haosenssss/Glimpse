import Foundation
import Testing
@testable import GlimpseCore

@Suite struct SSEParserTests {
    @Test func parsesContentDelta() throws {
        let line = #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#
        #expect(try SSEParser.parse(line: line) == [.content("Hi")])
    }

    @Test func parsesDataWithoutSpace() throws {
        let line = #"data:{"choices":[{"delta":{"content":"Hi"}}]}"#
        #expect(try SSEParser.parse(line: line) == [.content("Hi")])
    }

    @Test func parsesReasoningContent() throws {
        let line = #"data: {"choices":[{"delta":{"reasoning_content":"thinking"}}]}"#
        #expect(try SSEParser.parse(line: line) == [.reasoning("thinking")])
    }

    @Test func parsesOpenRouterReasoningField() throws {
        let line = #"data: {"choices":[{"delta":{"reasoning":"thinking"}}]}"#
        #expect(try SSEParser.parse(line: line) == [.reasoning("thinking")])
    }

    @Test func parsesDoneMarker() throws {
        #expect(try SSEParser.parse(line: "data: [DONE]") == [.done])
    }

    @Test(arguments: ["", ": keep-alive", "event: message", "id: 3", "data: not json"])
    func ignoresNonContentLines(line: String) throws {
        #expect(try SSEParser.parse(line: line).isEmpty)
    }

    @Test func ignoresEmptyDeltas() throws {
        let line = #"data: {"choices":[{"delta":{"content":""},"finish_reason":"stop"}]}"#
        #expect(try SSEParser.parse(line: line).isEmpty)
    }

    @Test func streamedErrorThrows() {
        let line = #"data: {"error":{"message":"model overloaded"}}"#
        #expect(throws: ChatError.server("model overloaded")) {
            try SSEParser.parse(line: line)
        }
    }

    @Test func streamedPlainStringErrorThrows() {
        #expect(throws: ChatError.server("quota exceeded")) {
            try SSEParser.parse(line: #"data: {"error":"quota exceeded"}"#)
        }
    }

    @Test func parsesNonStreamingCompletion() throws {
        let json = #"{"choices":[{"message":{"role":"assistant","content":"B"}}]}"#
        #expect(try SSEParser.parseCompletion(data: Data(json.utf8)) == "B")
    }

    @Test func nonStreamingWithoutContentThrows() {
        #expect(throws: ChatError.invalidResponse) {
            try SSEParser.parseCompletion(data: Data(#"{"choices":[]}"#.utf8))
        }
    }

    @Test func extractsErrorMessageFromJSON() {
        #expect(SSEParser.errorMessage(from: Data(#"{"error":{"message":"Invalid API key"}}"#.utf8)) == "Invalid API key")
        #expect(SSEParser.errorMessage(from: Data(#"{"message":"Bad model"}"#.utf8)) == "Bad model")
        #expect(SSEParser.errorMessage(from: Data("Gateway down".utf8)) == "Gateway down")
        #expect(SSEParser.errorMessage(from: Data()) == nil)
    }

    @Test func truncatesLongPlainErrorBodies() {
        let long = String(repeating: "x", count: 500)
        let message = SSEParser.errorMessage(from: Data(long.utf8))
        #expect((message?.count ?? 0) <= 121)
    }
}
