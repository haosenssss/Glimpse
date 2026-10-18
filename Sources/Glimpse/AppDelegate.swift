import AppKit
import GlimpseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuController: StatusMenuController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(settingsStore: SettingsStore(), keychain: KeychainStore())
        NSApp.mainMenu = Self.makeMainMenu()
        let menuController = StatusMenuController(coordinator: coordinator)
        self.menuController = menuController

        let failures = coordinator.registerGlobalHotkeys()
        if !coordinator.apiKey.isEmpty { coordinator.refreshModels() }
        menuController.report(failures)
        if coordinator.needsSetup {
            DispatchQueue.main.async { menuController.open() }
        }
    }

    /// Opening Glimpse from /Applications while it's already running pops the menu,
    /// since there is no window to bring forward.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menuController?.open()
        return false
    }

    /// Accessory apps still need an Edit menu, or ⌘C/⌘V/⌘A won't work in the input dialogs.
    private static func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Glimpse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        main.addItem(editItem)

        return main
    }
}
