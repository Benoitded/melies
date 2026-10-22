import AppKit
import AVFoundation
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

@main
struct MeliesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    /// `Melies --check-screen-access` only answers whether screen recording is allowed (exit code 0 or 1).
    /// A fresh process sees a switch turned on in System Settings at once, which the running app does not:
    /// the onboarding uses this to relaunch by itself.
    init() {
        if CommandLine.arguments.contains("--check-screen-access") {
            exit(CGPreflightScreenCaptureAccess() ? 0 : 1)
        }
    }
    @ObservedObject private var recorder = ScreenRecorder.shared
    @AppStorage("recordMicrophone") private var recordMicrophone = false
    @AppStorage("recordSystemAudio") private var recordSystemAudio = false

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
            Button(L("menu.combine")) { CombineWindowController.shared.show(current: EditorWindowController.shared.session.model?.url) }
            Toggle(L("set.audio.mic"), isOn: $recordMicrophone)
            Toggle(L("set.audio.system"), isOn: $recordSystemAudio)
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
            if Updater.shared.isAvailable {
                Button(L("menu.updates")) { Updater.shared.checkForUpdates() }
            }
            Button(L("menu.quit")) { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
    }
}


final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        TempFiles.sweep(olderThan: 0) // at quit nothing of ours in the temporary folder is still needed
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.global(qos: .utility).async { TempFiles.sweep() }
        NSApp.setActivationPolicy(.accessory)
        Appearance.apply()
        MainMenu.install()
        KeyboardShortcuts.onKeyUp(for: .openEditor) {
            Task { @MainActor in EditorWindowController.shared.openLatest() }
        }

        KeyboardShortcuts.onKeyUp(for: .record) {
            Task { @MainActor in ScreenRecorder.shared.toggle() }
        }

        Task { @MainActor in MCPServer.shared.startIfEnabled() }

        // Only from a real app bundle: test runs of the bare binary (and its missing translations) must not open it.
        if OnboardingWindowController.needed, Bundle.main.bundleURL.pathExtension == "app" {
            Task { @MainActor in OnboardingWindowController.shared.show() }
        }

        #if DEBUG || MELIES_HOOKS
        DebugHooks.run()
        #endif
    }

    /// "Open with Méliès" from Finder, or `open -a Melies file.mov`.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        Task { @MainActor in EditorWindowController.shared.open(url) }
    }
}
