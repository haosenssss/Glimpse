import Foundation
import Testing
@testable import GlimpseCore

@Suite(.serialized) struct KeychainStoreTests {
    let store = KeychainStore(service: "com.haosen.glimpse.tests.\(UUID().uuidString)", account: "api-key")

    @Test func savesUpdatesAndDeletes() throws {
        defer { try? store.delete() }
        #expect(store.read() == nil)

        try store.save("sk-one")
        #expect(store.read() == "sk-one")

        try store.save("sk-two")
        #expect(store.read() == "sk-two")

        try store.save("")
        #expect(store.read() == nil)
    }

    @Test func deletingMissingItemIsNotAnError() throws {
        try store.delete()
    }
}
