import AppKit
import ApplicationServices

enum PermissionChecker {
    enum Pane: String {
        case accessibility = "Privacy_Accessibility"
        case screenRecording = "Privacy_ScreenCapture"
    }

    static var hasAccessibility: Bool { AXIsProcessTrusted() }
    static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt that adds Glimpse to the Accessibility list.
    static func requestAccessibility() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
    }

    static func open(_ pane: Pane) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)") else { return }
        NSWorkspace.shared.open(url)
    }
}
