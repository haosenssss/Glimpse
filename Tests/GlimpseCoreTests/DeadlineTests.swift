import Foundation
import Testing
@testable import GlimpseCore

@Suite struct DeadlineTests {
    @Test func returnsResultWhenFastEnough() async throws {
        let value = try await Deadline.run(.seconds(5), onTimeout: ChatError.timeout(seconds: 5)) { 42 }
        #expect(value == 42)
    }

    @Test func throwsGivenErrorWhenTooSlow() async {
        await #expect(throws: ChatError.capture("Capture timed out")) {
            try await Deadline.run(.milliseconds(50), onTimeout: ChatError.capture("Capture timed out")) {
                try await Task.sleep(for: .seconds(5))
                return 0
            }
        }
    }

    @Test func propagatesOperationErrors() async {
        await #expect(throws: ChatError.emptyAnswer) {
            try await Deadline.run(.seconds(5), onTimeout: ChatError.timeout(seconds: 5)) { () async throws -> Int in
                throw ChatError.emptyAnswer
            }
        }
    }
}
