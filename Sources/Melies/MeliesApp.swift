import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct MeliesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra("Méliès", systemImage: "film") {
            Button("Ouvrir l'éditeur") { EditorWindowController.shared.openLatest() }
            Button("Ouvrir un fichier…") {
                EditorWindowController.shared.show()
                EditorWindowController.shared.session.chooseFile()
            }
            Divider()
            Button("Réglages et raccourcis…") { SettingsWindowController.shared.show() }
            Divider()
            Button("Quitter Méliès") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        KeyboardShortcuts.onKeyUp(for: .openEditor) {
            Task { @MainActor in EditorWindowController.shared.openLatest() }
        }
    }

    /// "Open with Méliès" from Finder, or `open -a Melies file.mov`.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in EditorWindowController.shared.open(url) }
    }
}
