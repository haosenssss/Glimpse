import AppKit
import GlimpseCore

/// The menu-bar icon and its menu. Everything — history, every setting — lives
/// in this menu; it's rebuilt each time it opens so it always shows current values.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    let coordinator: AppCoordinator
    private let statusItem: NSStatusItem
    private let menu = NSMenu(title: "Glimpse")
    private let screenshotPreview = ScreenshotPreview()

    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        let image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Glimpse")
        image?.isTemplate = true
        statusItem.button?.image = image
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu
    }

    /// Pops the menu open, e.g. on first launch when setup is still needed.
    func open() {
        statusItem.button?.performClick(nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        menu.removeAllItems()
        rootItems().forEach(menu.addItem)
    }

    private func rootItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if coordinator.needsSetup {
            items += [.info("⚠︎ Set the API Key and Model under Model ▸"), .separator()]
        }

        let cancel = ActionMenuItem("Cancel Current") { [weak self] in self?.coordinator.cancel() }
        cancel.isEnabled = coordinator.phase.isBusy
        items += [historyMenu(), cancel, .separator()]
        items += settingsMenus()
        let quit = ActionMenuItem("Quit Glimpse") { NSApp.terminate(nil) }
        items += [.separator(), quit.showingShortcut(coordinator.settings.quitHotkey)]
        return items
    }

    private func historyMenu() -> NSMenuItem {
        let entries = coordinator.history.entries
        let copyScreenshot: [NSMenuItem] = coordinator.lastCaptureJPEG.map { jpeg in
            [ActionMenuItem("Show Last Screenshot") { [weak self] in self?.screenshotPreview.show(jpeg: jpeg) }]
        } ?? []
        guard !entries.isEmpty else { return .submenu("History", items: [.info("No history yet")] + copyScreenshot) }

        let rows: [NSMenuItem] = entries.map { entry in
            let title = entry.summary(timeFormatter: timeFormatter)
            guard entry.answer != nil else { return .info(title) }
            let row = ActionMenuItem(title) { [weak self] in self?.coordinator.copyAnswer(entryID: entry.id) }
            row.toolTip = "Click to copy the full answer"
            return row
        }
        let clear = ActionMenuItem("Clear History") { [weak self] in self?.coordinator.clearHistory() }
        return .submenu("History", items: rows + [.separator()] + copyScreenshot + [clear])
    }

    /// Runs a dialog-opening `action` after the menu has finished closing, with Glimpse's
    /// hotkeys released so Return and Esc reach the dialog.
    func deferred(_ action: @escaping @MainActor () -> Void) -> () -> Void {
        {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.report(self.coordinator.performModal(action))
                }
            }
        }
    }

    func report(_ problems: [String]) {
        guard !problems.isEmpty else { return }
        Dialogs.showError(problems.joined(separator: "\n"))
    }
}
