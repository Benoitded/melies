import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct MeliesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var recorder = ScreenRecorder.shared

    var body: some Scene {
        MenuBarExtra("Méliès", systemImage: recorder.isRecording ? "record.circle.fill" : "film") {
            Button(recorder.isRecording ? "Arrêter l'enregistrement" : "Enregistrer l'écran") {
                ScreenRecorder.shared.toggle()
            }
            Text("Raccourci : \(KeyboardShortcuts.getShortcut(for: .record)?.description ?? "aucun")")
            Divider()
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

        KeyboardShortcuts.onKeyUp(for: .record) {
            Task { @MainActor in ScreenRecorder.shared.toggle() }
        }

        // Debug hooks: MELIES_OPEN=file.mov opens it, MELIES_SNAPSHOT=out.png saves a render and quits.
        let env = ProcessInfo.processInfo.environment
        if let path = env["MELIES_OPEN"] {
            Task { @MainActor in
                EditorWindowController.shared.open(URL(fileURLWithPath: path))
                if let out = env["MELIES_SNAPSHOT"] {
                    try? await Task.sleep(for: .seconds(2))
                    EditorWindowController.shared.snapshot(to: out)
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// "Open with Méliès" from Finder, or `open -a Melies file.mov`.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in EditorWindowController.shared.open(url) }
    }
}
