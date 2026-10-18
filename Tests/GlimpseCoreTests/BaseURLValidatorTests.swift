import Foundation
import Testing
@testable import GlimpseCore

@Suite struct BaseURLValidatorTests {
    @Test func acceptsHTTPSAndStripsTrailingSlash() throws {
        #expect(try BaseURLValidator.validate("  https://api.openai.com/v1/ ").absoluteString == "https://api.openai.com/v1")
    }

    @Test(arguments: ["http://localhost:11434/v1", "http://127.0.0.1:1234/v1", "http://[::1]:8080/v1"])
    func allowsPlainHTTPForLocalhost(raw: String) throws {
        #expect(try BaseURLValidator.validate(raw).scheme == "http")
    }

    @Test func rejectsPlainHTTPForRemoteHosts() {
        #expect(throws: ChatError.insecureBaseURL) {
            try BaseURLValidator.validate("http://api.example.com/v1")
        }
    }

    @Test(arguments: ["", "   ", "not a url", "ftp://example.com", "https://"])
    func rejectsInvalidURLs(raw: String) {
        #expect(throws: ChatError.invalidBaseURL) {
            try BaseURLValidator.validate(raw)
        }
    }
}
