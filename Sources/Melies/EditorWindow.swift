import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()

    let session = EditorSession()
    private var window: NSWindow?

    var isKey: Bool { window?.isKeyWindow ?? false }

    /// Hotkey entry point: show the editor on the newest recording.
    func openLatest() {
        session.openLatest()
        show()
    }

    func open(_ url: URL) {
        session.open(url)
        show()
    }

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 920, height: 580),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Méliès"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 640, height: 400)
            // An empty unified toolbar makes the title bar tall, so the traffic lights sit centered
            // on the same row as our own toolbar.
            let toolbar = NSToolbar(identifier: "melies.editor")
            toolbar.showsBaselineSeparator = false
            w.toolbar = toolbar
            w.toolbarStyle = .unified
            w.contentView = NSHostingView(rootView: EditorView(session: session, close: { [weak self] in self?.close() }))
            w.center()
            window = w
            session.onPinChange = { [weak w] pinned in w?.level = pinned ? .floating : .normal }
            session.pinned = UserDefaults.standard.bool(forKey: "alwaysOnTop")
            // Closing with the red button must also remove the Dock icon.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.session.model?.player.pause()
                    NSApp.setActivationPolicy(.accessory)
                }
            }
        }
        NSApp.setActivationPolicy(.regular) // Dock icon only while the editor is open
        MainMenu.install()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Debug helper: render the window content to a PNG (MELIES_SNAPSHOT=path).
    func snapshot(to path: String) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }

    func close() {
        session.model?.player.pause()
        window?.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show(tab: Int = 0) {
        if window == nil {
            let tabs = NSTabViewController()
            tabs.tabStyle = .toolbar
            tabs.title = L("settings.title")
            for (label, symbol, view) in [
                (L("set.tab.general"), "gearshape", AnyView(GeneralTab())),
                (L("set.tab.hotkeys"), "keyboard", AnyView(HotkeysTab())),
                (L("set.tab.advanced"), "gearshape.2", AnyView(AdvancedTab())),
            ] {
                let host = NSHostingController(rootView: view)
                host.sizingOptions = [.preferredContentSize]
                let item = NSTabViewItem(viewController: host)
                item.label = label
                item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
                tabs.addTabViewItem(item)
            }
            tabs.selectedTabViewItemIndex = tab
            let w = NSWindow(contentViewController: tabs)
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.level = .floating // stay visible above a pinned editor
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func snapshot(to path: String) {
        guard let view = window?.contentView?.superview ?? window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
