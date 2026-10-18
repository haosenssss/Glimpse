import Foundation
import Testing
@testable import GlimpseCore

@Suite struct AppSettingsTests {
    func makeDefaults() -> UserDefaults {
        let suite = "glimpse.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsAreUsable() {
        let settings = AppSettings.default
        #expect(settings.systemPrompt == DefaultPrompt.text)
        #expect(settings.timeoutSeconds == 60)
        #expect(settings.captureHotkey != settings.quitHotkey)
        #expect(settings.validationErrors.isEmpty)
    }

    @Test func storeReturnsDefaultsWhenEmpty() {
        #expect(SettingsStore(defaults: makeDefaults()).load() == .default)
    }

    @Test func storeRoundTripsSettings() {
        let store = SettingsStore(defaults: makeDefaults())
        let edited = AppSettings.default
            .with(\.baseURL, "https://api.example.com/v1")
            .with(\.model, "gpt-4o")
            .with(\.indicator, IndicatorSettings(size: 14, opacity: 0.5, centerX: 100, centerY: 200))

        store.save(edited)
        #expect(store.load() == edited)
    }

    @Test func withReturnsCopyLeavingOriginal() {
        let original = AppSettings.default
        let changed = original.with(\.model, "other")
        #expect(original.model != "other")
        #expect(changed.model == "other")
    }

    @Test func partialStoredJSONFallsBackToDefaults() throws {
        let defaults = makeDefaults()
        defaults.set(Data(#"{"model":"llava"}"#.utf8), forKey: SettingsStore.key)
        let loaded = SettingsStore(defaults: defaults).load()

        #expect(loaded.model == "llava")
        #expect(loaded.systemPrompt == DefaultPrompt.text)
        #expect(loaded.captureHotkey == AppSettings.default.captureHotkey)
    }

    @Test func corruptStoredDataFallsBackToDefaults() {
        let defaults = makeDefaults()
        defaults.set(Data("garbage".utf8), forKey: SettingsStore.key)
        #expect(SettingsStore(defaults: defaults).load() == .default)
    }

    @Test func identicalHotkeysAreReported() {
        let settings = AppSettings.default.with(\.quitHotkey, AppSettings.default.captureHotkey)
        #expect(settings.validationErrors.contains(.hotkeyConflict))
    }

    @Test func hotkeyDisplayUsesStandardModifierOrder() {
        let hotkey = Hotkey(keyCode: 5, modifiers: Hotkey.command | Hotkey.shift | Hotkey.control | Hotkey.option, keyLabel: "G")
        #expect(hotkey.displayString == "⌃⌥⇧⌘G")
    }

    @Test func commandPlusSingleKeyIsReservedByApps() {
        #expect(Hotkey(keyCode: 7, modifiers: Hotkey.command, keyLabel: "X").isReservedByApps)
        #expect(!Hotkey(keyCode: 7, modifiers: Hotkey.command | Hotkey.shift, keyLabel: "X").isReservedByApps)
        #expect(!Hotkey(keyCode: 7, modifiers: Hotkey.control | Hotkey.option, keyLabel: "X").isReservedByApps)
        #expect(!Hotkey(keyCode: 122, modifiers: Hotkey.command, keyLabel: "F1").isReservedByApps)
    }

    @Test func savedReservedHotkeysFallBackToDefaults() {
        let store = SettingsStore(defaults: makeDefaults())
        let commandX = Hotkey(keyCode: 7, modifiers: Hotkey.command, keyLabel: "X")
        let commandC = Hotkey(keyCode: 8, modifiers: Hotkey.command, keyLabel: "C")
        store.save(AppSettings.default.with(\.quitHotkey, commandX).with(\.captureHotkey, commandC).with(\.model, "m"))

        let loaded = store.load()
        #expect(loaded.quitHotkey == AppSettings.default.quitHotkey)
        #expect(loaded.captureHotkey == AppSettings.default.captureHotkey)
        #expect(loaded.model == "m")
    }

    @Test func indicatorSettingsAreClamped() {
        let clamped = IndicatorSettings(size: 100, opacity: 5, centerX: nil, centerY: nil).clamped()
        #expect(clamped.size == IndicatorSettings.sizeRange.upperBound)
        #expect(clamped.opacity == IndicatorSettings.opacityRange.upperBound)
    }
}
