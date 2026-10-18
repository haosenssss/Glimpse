import AppKit
import GlimpseCore

/// A menu item that runs a closure, so menus can be built without one selector per action.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, checked: Bool = false, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
        state = checked ? .on : .off
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() {
        handler()
    }
}

extension NSMenuItem {
    static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        items.forEach(menu.addItem)
        item.submenu = menu
        return item
    }

    /// Shows a hotkey right-aligned, the way macOS menus show key equivalents.
    /// Keys a menu can't display that way are appended to the title instead.
    func showingShortcut(_ hotkey: Hotkey) -> Self {
        guard let equivalent = Self.keyEquivalent(for: hotkey) else {
            title = "\(title)  \(hotkey.displayString)"
            return self
        }
        keyEquivalent = equivalent
        keyEquivalentModifierMask = Self.modifierMask(for: hotkey)
        return self
    }

    private static func keyEquivalent(for hotkey: Hotkey) -> String? {
        guard hotkey.keyLabel.count == 1, let scalar = hotkey.keyLabel.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(scalar) || CharacterSet.punctuationCharacters.contains(scalar)
        else { return nil }
        return hotkey.keyLabel.lowercased()
    }

    private static func modifierMask(for hotkey: Hotkey) -> NSEvent.ModifierFlags {
        var mask: NSEvent.ModifierFlags = []
        if hotkey.modifiers & Hotkey.command != 0 { mask.insert(.command) }
        if hotkey.modifiers & Hotkey.shift != 0 { mask.insert(.shift) }
        if hotkey.modifiers & Hotkey.option != 0 { mask.insert(.option) }
        if hotkey.modifiers & Hotkey.control != 0 { mask.insert(.control) }
        return mask
    }
}
