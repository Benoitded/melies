import AppKit
import SwiftUI

@MainActor
final class EditorWindowController {
    static let shared = EditorWindowController()

    let session = EditorSession()
    private var window: NSWindow?

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
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 560, height: 380)
            w.appearance = NSAppearance(named: .darkAqua)
            w.contentView = NSHostingView(rootView: EditorView(session: session, close: { [weak self] in self?.close() }))
            w.center()
            window = w
            session.onPinChange = { [weak w] pinned in w?.level = pinned ? .floating : .normal }
            // Closing with the red button must also remove the Dock icon.
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated { NSApp.setActivationPolicy(.accessory) }
            }
        }
        NSApp.setActivationPolicy(.regular) // Dock icon only while the editor is open
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    /// Debug helper: render the window content to a PNG (MELIES_SNAPSHOT=path).
    func snapshot(to path: String) {
        guard let view = window?.contentView,
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

    func show() {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            w.title = L("settings.title")
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
