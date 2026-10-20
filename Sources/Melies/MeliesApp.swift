import AppKit
import KeyboardShortcuts
import SwiftUI

@main
struct MeliesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var recorder = ScreenRecorder.shared

    var body: some Scene {
        // While recording, this icon is removed: the red timer is then the only item, and one click stops.
        MenuBarExtra("Méliès", systemImage: "film", isInserted: Binding(get: { !recorder.isRecording }, set: { _ in })) {
            Button(L("menu.record.start")) {
                ScreenRecorder.shared.toggle()
            }
            Text(L("menu.shortcut", KeyboardShortcuts.getShortcut(for: .record) == nil ? L("menu.none") : shortcutLabel(.record)))
            Divider()
            Button(L("menu.open_editor")) { EditorWindowController.shared.openLatest() }
            Button(L("menu.open_file")) {
                EditorWindowController.shared.show()
                EditorWindowController.shared.session.chooseFile()
            }
            Divider()
            Button(L("menu.settings")) { SettingsWindowController.shared.show() }
            Button(L("menu.help")) { OnboardingWindowController.shared.show() }
            Divider()
            Button(L("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
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

        if OnboardingWindowController.needed {
            Task { @MainActor in OnboardingWindowController.shared.show() }
        }

        if let out = ProcessInfo.processInfo.environment["MELIES_ONBOARDING_SNAPSHOT"] {
            Task { @MainActor in
                OnboardingWindowController.shared.show()
                try? await Task.sleep(for: .seconds(2.2))
                OnboardingWindowController.shared.snapshot(to: out)
                NSApp.terminate(nil)
            }
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
