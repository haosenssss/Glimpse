import AppKit
import Carbon

/// Pastes text at the current cursor by briefly borrowing the clipboard, then
/// putting back whatever was there before.
@MainActor
enum TextInserter {
    enum Outcome {
        case pasted
        /// Couldn't send ⌘V (no Accessibility permission, or a password field has
        /// secure input on); the answer is left on the clipboard instead.
        case copiedOnly
    }

    private typealias Snapshot = [[(NSPasteboard.PasteboardType, Data)]]

    /// Long enough for slow apps (Electron, remote desktops) to read the pasteboard first.
    private static let restoreDelay: TimeInterval = 1.0
    private static let vKeyCode: CGKeyCode = 9
    /// Tells clipboard managers to ignore this short-lived entry (nspasteboard.org).
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func insert(_ text: String) -> Outcome {
        let pasteboard = NSPasteboard.general
        guard AXIsProcessTrusted(), !IsSecureEventInputEnabled() else {
            copy(text)
            return .copiedOnly
        }

        let saved = snapshot(of: pasteboard)
        write(text, to: pasteboard, transient: true)
        let ourChange = pasteboard.changeCount
        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            // Leave the clipboard alone if something else wrote to it meanwhile.
            guard pasteboard.changeCount == ourChange else { return }
            restore(saved, to: pasteboard)
        }
        return .pasted
    }

    static func copy(_ text: String) {
        write(text, to: .general, transient: false)
    }

    private static func write(_ text: String, to pasteboard: NSPasteboard, transient: Bool) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient { item.setData(Data(), forType: transientType) }
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
        (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
    }

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { entries -> NSPasteboardItem in
            let item = NSPasteboardItem()
            entries.forEach { type, data in item.setData(data, forType: type) }
            return item
        }
        pasteboard.writeObjects(items)
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        for isDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: isDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}
