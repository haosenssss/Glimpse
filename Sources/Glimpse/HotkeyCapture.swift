import AppKit
import GlimpseCore

/// Turns a key-down event into a `Hotkey`, or `nil` when it isn't a usable global shortcut.
enum HotkeyCapture {
    private static let functionKeyLabels: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    private static let specialKeyLabels: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    static func isPlainEscape(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(KeyCode.escape)
            && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
    }

    static func hotkey(from event: NSEvent) -> Hotkey? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let modifiers = carbonModifiers(flags)
        let isFunctionKey = functionKeyLabels[event.keyCode] != nil
        // Shift alone would steal ordinary typing, so require ⌘, ⌃ or ⌥ (F-keys excepted).
        let hasStrongModifier = modifiers & (Hotkey.command | Hotkey.control | Hotkey.option) != 0
        guard hasStrongModifier || isFunctionKey, let label = label(for: event) else { return nil }
        return Hotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= Hotkey.command }
        if flags.contains(.shift) { modifiers |= Hotkey.shift }
        if flags.contains(.option) { modifiers |= Hotkey.option }
        if flags.contains(.control) { modifiers |= Hotkey.control }
        return modifiers
    }

    private static func label(for event: NSEvent) -> String? {
        if let label = functionKeyLabels[event.keyCode] ?? specialKeyLabels[event.keyCode] { return label }
        guard let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty,
              characters.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) })
        else { return nil }
        return characters
    }
}
