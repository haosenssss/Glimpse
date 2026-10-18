import Foundation
import Testing
@testable import GlimpseCore

@Suite struct DefaultPromptTests {
    func makeDefaults() -> UserDefaults {
        let suite = "glimpse.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func store(prompt: String, in defaults: UserDefaults) {
        let settings = AppSettings.default.with(\.systemPrompt, prompt)
        defaults.set(try! JSONEncoder().encode(settings), forKey: SettingsStore.key)
    }

    @Test func everySavedOldDefaultIsUpgradedToCurrentDefault() {
        #expect(DefaultPrompt.previousVersions.count >= 2)
        for oldDefault in DefaultPrompt.previousVersions {
            let defaults = makeDefaults()
            store(prompt: oldDefault, in: defaults)
            #expect(SettingsStore(defaults: defaults).load().systemPrompt == DefaultPrompt.text)
        }
    }

    @Test func customPromptIsLeftAlone() {
        let defaults = makeDefaults()
        store(prompt: "My own prompt", in: defaults)

        #expect(SettingsStore(defaults: defaults).load().systemPrompt == "My own prompt")
    }

    @Test func currentDefaultIsNotAPreviousVersion() {
        #expect(!DefaultPrompt.previousVersions.contains(DefaultPrompt.text))
    }

    @Test func promptAsksForParagraphStepsAndCommonSymbols() {
        let prompt = DefaultPrompt.text
        #expect(prompt.contains("one short paragraph"))
        #expect(prompt.contains("No Markdown"))
        #expect(prompt.contains("Thus, the answer is"))
        #expect(!prompt.contains("numbered"))
        #expect(!prompt.contains("Answer:"))
    }

    @Test func exampleStepsAreUnnumbered() throws {
        let example = try #require(DefaultPrompt.text.components(separatedBy: "Example of a worked solution:").last)
        let lines = example.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(lines.count >= 2)
        #expect(lines.allSatisfy { $0.first?.isNumber != true })
    }
}
