import AppKit
import GlimpseCore

/// The settings submenus. Choices apply immediately; values that need typing open a small dialog.
extension StatusMenuController {
    private static let timeoutOptions: [Double] = [30, 60, 90, 120, 180, 300]
    private static let sizeOptions: [Double] = [6, 8, 10, 12, 14, 16, 20, 24]
    private static let opacityOptions: [Double] = [0.15, 0.25, 0.35, 0.5, 0.75, 1]
    private static let maxTitleValueLength = 36

    func settingsMenus() -> [NSMenuItem] {
        [modelMenu(), promptMenu(), shortcutMenu(), indicatorMenu(), permissionMenu()]
    }

    // MARK: - Model

    private func modelMenu() -> NSMenuItem {
        let settings = coordinator.settings
        let key = coordinator.apiKey
        let keyLabel = key.isEmpty ? "Not Set" : "••••" + key.suffix(4)

        return .submenu("Model", items: [
            ActionMenuItem("Base URL: \(Self.shorten(settings.baseURL))", handler: deferred { [weak self] in self?.editBaseURL() }),
            ActionMenuItem("API Key: \(keyLabel)", handler: deferred { [weak self] in self?.editAPIKey() }),
            modelPicker(current: settings.model),
            timeoutMenu(current: settings.timeoutSeconds),
        ])
    }

    private func modelPicker(current: String) -> NSMenuItem {
        var items: [NSMenuItem] = ModelCatalog.grouped(coordinator.availableModels).flatMap { group -> [NSMenuItem] in
            let rows = group.models.map { modelRow($0, current: current) }
            guard let name = group.name else { return rows }
            let provider = NSMenuItem.submenu(name, items: rows)
            provider.state = group.models.contains(current) ? .on : .off
            return [provider]
        }
        if coordinator.isFetchingModels {
            items.append(.info("Loading models…"))
        } else if let error = coordinator.modelListError {
            items.append(.info("⚠︎ \(error)"))
        } else if items.isEmpty {
            items.append(.info("No model list loaded"))
        }
        items += [
            .separator(),
            ActionMenuItem("Enter Model Name…", handler: deferred { [weak self] in self?.editModelName() }),
            ActionMenuItem("Refresh Model List") { [weak self] in self?.coordinator.refreshModels() },
        ]
        return .submenu("Model: \(current.isEmpty ? "Not Set" : Self.shorten(current))", items: items)
    }

    private func modelRow(_ name: String, current: String) -> NSMenuItem {
        ActionMenuItem(name, checked: name == current) { [weak self] in
            self?.coordinator.update { $0.with(\.model, name) }
        }
    }

    private func timeoutMenu(current: Double) -> NSMenuItem {
        let items = Self.timeoutOptions.map { seconds in
            ActionMenuItem("\(Int(seconds))s", checked: seconds == current) { [weak self] in
                self?.coordinator.update { $0.with(\.timeoutSeconds, seconds) }
            }
        }
        return .submenu("Timeout: \(Int(current))s", items: items)
    }

    private func editBaseURL() {
        guard let text = Dialogs.text(
            title: "Base URL", message: "OpenAI-compatible endpoint, e.g. https://api.openai.com/v1",
            initial: coordinator.settings.baseURL, placeholder: "https://api.openai.com/v1"
        ) else { return }
        do {
            let url = try BaseURLValidator.validate(text)
            coordinator.update { $0.with(\.baseURL, url.absoluteString) }
            coordinator.refreshModels()
        } catch {
            Dialogs.showError(ChatError.wrap(error).shortDescription)
        }
    }

    private func editAPIKey() {
        guard let key = Dialogs.text(
            title: "API Key", message: "Stored in your login Keychain.",
            initial: coordinator.apiKey, placeholder: "sk-…", secure: true
        ) else { return }
        do {
            try coordinator.setAPIKey(key)
            coordinator.refreshModels()
        } catch {
            Dialogs.showError("Could not save the API key to the Keychain.")
        }
    }

    private func editModelName() {
        guard let name = Dialogs.text(
            title: "Model", message: "Must be a model that accepts images.",
            initial: coordinator.settings.model, placeholder: "gpt-4o"
        ) else { return }
        coordinator.update { $0.with(\.model, name.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    // MARK: - Prompt

    private func promptMenu() -> NSMenuItem {
        let isDefault = coordinator.settings.systemPrompt == DefaultPrompt.text
        let reset = ActionMenuItem("Reset to Default") { [weak self] in
            self?.coordinator.update { $0.with(\.systemPrompt, DefaultPrompt.text) }
        }
        reset.isEnabled = !isDefault
        return .submenu("System Prompt", items: [
            .info(isDefault ? "Using the default prompt" : "Using a custom prompt"),
            ActionMenuItem("Edit…", handler: deferred { [weak self] in self?.editPrompt() }),
            reset,
        ])
    }

    private func editPrompt() {
        guard let prompt = Dialogs.editPrompt(initial: coordinator.settings.systemPrompt) else { return }
        coordinator.update { $0.with(\.systemPrompt, prompt) }
    }

    // MARK: - Shortcuts

    private func shortcutMenu() -> NSMenuItem {
        let settings = coordinator.settings
        return .submenu("Shortcuts", items: [
            shortcutRow("Change Capture Shortcut…", current: settings.captureHotkey) { [weak self] in
                self?.recordShortcut(name: "Capture", keyPath: \.captureHotkey)
            },
            shortcutRow("Change Quit Shortcut…", current: settings.quitHotkey) { [weak self] in
                self?.recordShortcut(name: "Quit", keyPath: \.quitHotkey)
            },
            .separator(),
            .info("When ready: Return pastes, Esc discards"),
        ])
    }

    /// Shows the current shortcut right-aligned, the way macOS menus show key equivalents.
    private func shortcutRow(_ title: String, current: Hotkey, action: @escaping @MainActor () -> Void) -> NSMenuItem {
        let item = ActionMenuItem(title, handler: deferred(action))
        guard let equivalent = Self.keyEquivalent(for: current) else {
            item.title = "\(title)  \(current.displayString)"
            return item
        }
        item.keyEquivalent = equivalent
        item.keyEquivalentModifierMask = Self.modifierMask(for: current)
        return item
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

    /// Runs inside `performModal`, so the current shortcuts can't swallow the keystroke being recorded.
    private func recordShortcut(name: String, keyPath: WritableKeyPath<AppSettings, Hotkey>) {
        guard let hotkey = Dialogs.recordShortcut(for: name) else { return }
        report(coordinator.update { $0.with(keyPath, hotkey) })
    }

    // MARK: - Indicator

    private func indicatorMenu() -> NSMenuItem {
        let current = coordinator.settings.indicator
        let sizes = Self.sizeOptions.map { size in
            ActionMenuItem("\(Int(size)) pt", checked: size == current.size) { [weak self] in
                self?.updateIndicator { IndicatorSettings(size: size, opacity: $0.opacity, centerX: $0.centerX, centerY: $0.centerY) }
            }
        }
        let opacities = Self.opacityOptions.map { opacity in
            ActionMenuItem("\(Int(opacity * 100))%", checked: abs(opacity - current.opacity) < 0.001) { [weak self] in
                self?.updateIndicator { IndicatorSettings(size: $0.size, opacity: opacity, centerX: $0.centerX, centerY: $0.centerY) }
            }
        }
        let position = coordinator.isEditingIndicator
            ? ActionMenuItem("Done Adjusting Position") { [weak self] in self?.coordinator.endIndicatorEditing() }
            : ActionMenuItem("Adjust Position…") { [weak self] in self?.coordinator.beginIndicatorEditing() }

        var items: [NSMenuItem] = [
            .submenu("Size: \(Int(current.size)) pt", items: sizes),
            .submenu("Opacity: \(Int(current.opacity * 100))%", items: opacities),
            position,
        ]
        if coordinator.isEditingIndicator {
            items.append(.info("Drag the indicator, then choose Done"))
        }
        return .submenu("Indicator", items: items)
    }

    private func updateIndicator(_ change: @escaping (IndicatorSettings) -> IndicatorSettings) {
        coordinator.update { $0.with(\.indicator, change($0.indicator).clamped()) }
    }

    // MARK: - Permissions

    private func permissionMenu() -> NSMenuItem {
        let rows = [
            permissionRow("Accessibility", granted: PermissionChecker.hasAccessibility) {
                PermissionChecker.requestAccessibility()
                PermissionChecker.open(.accessibility)
            },
            permissionRow("Screen Recording", granted: PermissionChecker.hasScreenRecording) {
                PermissionChecker.requestScreenRecording()
                PermissionChecker.open(.screenRecording)
            },
        ]
        let allGranted = PermissionChecker.hasAccessibility && PermissionChecker.hasScreenRecording
        return .submenu(allGranted ? "Permissions" : "Permissions ⚠︎", items: rows)
    }

    private func permissionRow(_ name: String, granted: Bool, request: @escaping () -> Void) -> NSMenuItem {
        granted ? .info("✓ \(name)") : ActionMenuItem("Grant \(name)…", handler: request)
    }

    // MARK: - Helpers

    private static func shorten(_ text: String) -> String {
        text.count > maxTitleValueLength ? String(text.prefix(maxTitleValueLength)) + "…" : text
    }
}
