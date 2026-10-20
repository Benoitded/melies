import AppKit

/// Targets for the standard Mac menu items that are specific to Méliès.
@MainActor
final class MenuActions: NSObject, NSMenuItemValidation {
    static let shared = MenuActions()

    private var session: EditorSession { EditorWindowController.shared.session }

    @objc func openSettings() { SettingsWindowController.shared.show() }
    @objc func showHelp() { OnboardingWindowController.shared.show() }

    @objc func openFile() {
        EditorWindowController.shared.show()
        session.chooseFile()
    }

    @objc func loadClipboard() {
        EditorWindowController.shared.show()
        session.loadFromPasteboard()
    }

    @objc func zoomIn() { session.model?.zoomIn() }
    @objc func zoomOut() { session.model?.zoomOut() }
    @objc func zoomActual() { session.model?.zoomActual() }
    @objc func zoomFit() { session.model?.zoomToFit() }

    @objc func copyVideo() { Task { await session.model?.copy() } }
    @objc func saveVideo() { Task { await session.model?.save() } }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copyVideo), #selector(saveVideo), #selector(zoomIn), #selector(zoomOut),
             #selector(zoomActual), #selector(zoomFit):
            return session.model != nil && EditorWindowController.shared.isKey
        default:
            return true
        }
    }
}

/// The standard macOS menu bar: Méliès, File, Edit, Window, Help (⌘, ⌘O ⌘W ⌘M ⌘H ⌘Q ⌘Z ...).
@MainActor
enum MainMenu {
    private static var rebuilding = false
    private static var watching = false

    /// SwiftUI empties and refills the main menu in place whenever its scenes change, so we
    /// rebuild our items inside the same NSMenu and re-check whenever it is modified.
    static func install() {
        guard !rebuilding else { return }
        rebuilding = true
        defer { rebuilding = false }

        let main = NSApp.mainMenu ?? NSMenu()
        main.removeAllItems()
        main.addItem(submenuItem(appMenu()))
        main.addItem(submenuItem(fileMenu()))
        main.addItem(submenuItem(editMenu()))
        main.addItem(submenuItem(viewMenu()))
        let window = windowMenu()
        main.addItem(submenuItem(window))
        let help = helpMenu()
        main.addItem(submenuItem(help))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
        NSApp.helpMenu = help

        if !watching {
            watching = true
            for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification, NSMenu.didChangeItemNotification] {
                NotificationCenter.default.addObserver(forName: name, object: main, queue: .main) { _ in
                    MainActor.assumeIsolated { scheduleCheck() }
                }
            }
        }
    }

    private static func scheduleCheck() {
        guard !rebuilding else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            MainActor.assumeIsolated {
                let items = NSApp.mainMenu?.items ?? []
                let ours = items.count == 6 && items[1].submenu?.title == L("mm.file")
                if !ours { install() }
            }
        }
    }

    private static func submenuItem(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ modifiers: NSEvent.ModifierFlags = [.command], target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Méliès")
        add(menu, L("mm.about"), #selector(NSApplication.orderFrontStandardAboutPanel(_:)))
        menu.addItem(.separator())
        add(menu, L("mm.settings"), #selector(MenuActions.openSettings), ",", target: MenuActions.shared)
        menu.addItem(.separator())
        add(menu, L("mm.hide"), #selector(NSApplication.hide(_:)), "h")
        add(menu, L("mm.hide_others"), #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(menu, L("mm.show_all"), #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        add(menu, L("menu.quit"), #selector(NSApplication.terminate(_:)), "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: L("mm.file"))
        add(menu, L("mm.open"), #selector(MenuActions.openFile), "o", target: MenuActions.shared)
        add(menu, L("sc.paste"), #selector(MenuActions.loadClipboard), "v", [.command, .shift], target: MenuActions.shared)
        menu.addItem(.separator())
        add(menu, L("sc.save"), #selector(MenuActions.saveVideo), "s", target: MenuActions.shared)
        menu.addItem(.separator())
        add(menu, L("mm.close"), #selector(NSWindow.performClose(_:)), "w")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: L("mm.edit"))
        add(menu, L("mm.undo"), Selector(("undo:")), "z")
        add(menu, L("mm.redo"), Selector(("redo:")), "z", [.command, .shift])
        menu.addItem(.separator())
        add(menu, L("tip.copy"), #selector(MenuActions.copyVideo), "c", target: MenuActions.shared)
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: L("mm.view"))
        add(menu, L("mm.zoom_in"), #selector(MenuActions.zoomIn), "+", target: MenuActions.shared)
        add(menu, L("mm.zoom_out"), #selector(MenuActions.zoomOut), "-", target: MenuActions.shared)
        add(menu, L("mm.zoom_actual"), #selector(MenuActions.zoomActual), "0", target: MenuActions.shared)
        add(menu, L("mm.zoom_fit"), #selector(MenuActions.zoomFit), "1", target: MenuActions.shared)
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: L("mm.window"))
        add(menu, L("mm.minimize"), #selector(NSWindow.performMiniaturize(_:)), "m")
        add(menu, L("mm.zoom"), #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        add(menu, L("mm.front"), #selector(NSApplication.arrangeInFront(_:)))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: L("mm.help"))
        add(menu, L("menu.help"), #selector(MenuActions.showHelp), "?", target: MenuActions.shared)
        return menu
    }
}
