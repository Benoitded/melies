import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@main
struct MeliesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var recorder = ScreenRecorder.shared

    var body: some Scene {
        // While recording, this icon is removed: the red timer is then the only item, and one click stops.
        MenuBarExtra("Méliès", systemImage: "film", isInserted: Binding(get: { !recorder.isRecording }, set: { _ in })) {
            Button(L("menu.reopen")) { EditorWindowController.shared.openLatest() }
                .keyboardShortcut(swiftUIShortcut(.openEditor))
            Divider()
            Button(L("menu.record.start")) { ScreenRecorder.shared.toggle() }
                .keyboardShortcut(swiftUIShortcut(.record))
            Button(L("menu.open_file")) {
                EditorWindowController.shared.show()
                EditorWindowController.shared.session.chooseFile()
            }
            Menu(L("menu.more")) {
                Button(L("menu.show_folder")) { NSWorkspace.shared.open(LatestRecording.watchedFolder()) }
                Button(L("menu.help")) { OnboardingWindowController.shared.show() }
            }
            Divider()
            Toggle(L("set.startup.launch"), isOn: Binding(
                get: { SMAppService.mainApp.status == .enabled },
                set: { on in
                    if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                }
            ))
            Button { SettingsWindowController.shared.show() } label: {
                Label(L("mm.settings"), systemImage: "gearshape")
            }
            .keyboardShortcut(",")
            Button(L("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Appearance.apply()
        MainMenu.install()
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

        if let out = ProcessInfo.processInfo.environment["MELIES_SETTINGS_SNAPSHOT"] {
            let tab = Int(ProcessInfo.processInfo.environment["MELIES_SETTINGS_TAB"] ?? "0") ?? 0
            Task { @MainActor in
                SettingsWindowController.shared.show(tab: tab)
                try? await Task.sleep(for: .seconds(1.5))
                SettingsWindowController.shared.snapshot(to: out)
                NSApp.terminate(nil)
            }
        }

        // Debug: MELIES_MENU_DUMP=1 prints the main menu after launch settles.
        if ProcessInfo.processInfo.environment["MELIES_MENU_DUMP"] != nil {
            Task { @MainActor in
                EditorWindowController.shared.show()
                try? await Task.sleep(for: .seconds(1.5))
                for top in NSApp.mainMenu?.items ?? [] {
                    print("[menu] \(top.submenu?.title ?? "?")")
                    for item in top.submenu?.items ?? [] where !item.isSeparatorItem {
                        let keys = item.keyEquivalent.isEmpty ? "" : "  (\(item.keyEquivalentModifierMask.contains(.shift) ? "shift " : "")cmd+\(item.keyEquivalent))"
                        print("[menu]    \(item.title)\(keys)")
                    }
                }
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
