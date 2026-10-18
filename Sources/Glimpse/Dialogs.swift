import AppKit
import GlimpseCore

/// Small modal prompts for the few settings that need typing. Each one activates
/// Glimpse while open and hands focus back to the previous app afterwards.
@MainActor
enum Dialogs {
    private static let fieldWidth: CGFloat = 360
    private static let promptEditorSize = NSSize(width: 460, height: 240)

    static func text(title: String, message: String, initial: String, placeholder: String, secure: Bool = false) -> String? {
        let field: NSTextField = secure ? NSSecureTextField() : NSTextField()
        field.stringValue = initial
        field.placeholderString = placeholder
        field.frame = NSRect(x: 0, y: 0, width: fieldWidth, height: 24)

        let alert = makeAlert(title: title, message: message, buttons: ["Save", "Cancel"])
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        return run(alert) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    static func editPrompt(initial: String) -> String? {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame = NSRect(origin: .zero, size: promptEditorSize)
        scroll.borderType = .bezelBorder
        let textView = scroll.documentView as? NSTextView
        textView?.string = initial
        textView?.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView?.isRichText = false
        textView?.isAutomaticQuoteSubstitutionEnabled = false
        textView?.isAutomaticDashSubstitutionEnabled = false

        let alert = makeAlert(title: "System Prompt", message: "The only instruction the model gets besides the screenshot.", buttons: ["Save", "Cancel"])
        alert.accessoryView = scroll
        alert.window.initialFirstResponder = textView
        return run(alert) == .alertFirstButtonReturn ? textView?.string : nil
    }

    /// Waits for a key combination; Esc or Cancel returns `nil`.
    static func recordShortcut(for name: String) -> Hotkey? {
        let alert = makeAlert(
            title: "Press the new \(name) shortcut",
            message: "Use ⌘, ⌃ or ⌥ together with a key (F-keys work alone). Esc cancels.",
            buttons: ["Cancel"]
        )
        var recorded: Hotkey?
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if HotkeyCapture.isPlainEscape(event) {
                NSApp.abortModal()
            } else if let hotkey = HotkeyCapture.hotkey(from: event) {
                recorded = hotkey
                NSApp.stopModal(withCode: .OK)
            } else {
                NSSound.beep()
            }
            return nil
        }
        defer { monitor.map(NSEvent.removeMonitor) }
        _ = run(alert)
        return recorded
    }

    static func showError(_ message: String) {
        let alert = makeAlert(title: "Glimpse", message: message, buttons: ["OK"])
        alert.alertStyle = .warning
        _ = run(alert)
    }

    private static func makeAlert(title: String, message: String, buttons: [String]) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        buttons.forEach { alert.addButton(withTitle: $0) }
        return alert
    }

    private static func run(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let previous = NSWorkspace.shared.frontmostApplication
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if let previous, previous != NSRunningApplication.current {
            previous.activate()
        }
        return response
    }
}
