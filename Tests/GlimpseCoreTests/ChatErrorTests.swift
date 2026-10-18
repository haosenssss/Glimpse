import Foundation
import Testing
@testable import GlimpseCore

@Suite struct ChatErrorTests {
    @Test func httpErrorIncludesStatusAndServerMessage() {
        #expect(ChatError.http(status: 401, message: "Invalid API key").shortDescription == "401 Invalid API key")
    }

    @Test func httpErrorFallsBackToStandardReason() {
        #expect(ChatError.http(status: 500, message: nil).shortDescription == "500 internal server error")
    }

    @Test func timeoutShowsSeconds() {
        #expect(ChatError.timeout(seconds: 60).shortDescription == "Timeout (60s)")
    }

    @Test func wrapsArbitraryErrors() {
        #expect(ChatError.wrap(ChatError.emptyAnswer) == .emptyAnswer)
        #expect(ChatError.wrap(URLError(.notConnectedToInternet)) == .network("No internet connection"))
    }
}
