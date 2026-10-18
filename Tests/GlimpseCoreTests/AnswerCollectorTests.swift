import Foundation
import Testing
@testable import GlimpseCore

@Suite struct AnswerCollectorTests {
    func stream(_ events: [ChatEvent], error: Error? = nil) -> AsyncThrowingStream<ChatEvent, Error> {
        AsyncThrowingStream { continuation in
            events.forEach { continuation.yield($0) }
            continuation.finish(throwing: error)
        }
    }

    @Test func joinsContentAndIgnoresReasoning() async throws {
        let events: [ChatEvent] = [.reasoning("hmm"), .content("Hello"), .content(" world"), .done]
        let answer = try await AnswerCollector.collect(events: stream(events), timeout: .seconds(5))
        #expect(answer == "Hello world")
    }

    @Test func emptyAnswerThrows() async {
        await #expect(throws: ChatError.emptyAnswer) {
            try await AnswerCollector.collect(events: stream([.reasoning("hmm"), .done]), timeout: .seconds(5))
        }
    }

    @Test func streamErrorsPropagate() async {
        await #expect(throws: ChatError.server("boom")) {
            try await AnswerCollector.collect(events: stream([.content("a")], error: ChatError.server("boom")), timeout: .seconds(5))
        }
    }

    @Test func hangingStreamTimesOut() async {
        let neverEnding = AsyncThrowingStream<ChatEvent, Error> { _ in }
        await #expect(throws: ChatError.timeout(seconds: 0)) {
            try await AnswerCollector.collect(events: neverEnding, timeout: .milliseconds(100))
        }
    }
}
