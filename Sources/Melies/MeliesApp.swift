import AppKit
import AVFoundation
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

/// Debug: sample annotations used by MELIES_ANNOTATION_DEMO.
func demoAnnotations() -> [Annotation] {
    func make(_ kind: AnnotationKind, _ p1: CGPoint, _ p2: CGPoint, color: RGBA, width: Double, text: String = "") -> Annotation {
        Annotation(kind: kind, start: 0.5, end: 3.5, p1: p1, p2: p2, color: color, width: width,
                   arrow: .block, rect: .rounded, text: text, font: .sans, bold: true, box: .badge)
    }
    return [
        make(.arrow, CGPoint(x: 0.12, y: 0.82), CGPoint(x: 0.40, y: 0.50), color: .red, width: 7),
        make(.rect, CGPoint(x: 0.55, y: 0.18), CGPoint(x: 0.88, y: 0.55), color: .yellow, width: 4),
        make(.text, CGPoint(x: 0.08, y: 0.08), CGPoint(x: 0.08, y: 0.08), color: .blue, width: 34, text: "Nouveau !"),
    ]
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

        // Debug: MELIES_EXPORT_TEST=out.mp4 with MELIES_OPEN=in.mp4 exports with a crop and zoom animation.
        if let out = ProcessInfo.processInfo.environment["MELIES_EXPORT_TEST"],
           let input = ProcessInfo.processInfo.environment["MELIES_OPEN"] {
            Task { @MainActor in
                let asset = AVURLAsset(url: URL(fileURLWithPath: input))
                let points = [
                    ZoomPoint(time: 1.0, scale: 2, center: CGPoint(x: 0.25, y: 0.5), transition: 0.5, ease: .smooth),
                    ZoomPoint(time: 3.0, scale: 1, center: CGPoint(x: 0.5, y: 0.5), transition: 0.5, ease: .smooth),
                ]
                do {
                    let duration = try await asset.load(.duration)
                    let notes = ProcessInfo.processInfo.environment["MELIES_ANNOTATION_DEMO"] != nil ? demoAnnotations() : []
                    try await VideoExport.run(asset: asset, range: CMTimeRange(start: .zero, duration: duration), points: points, annotations: notes, to: URL(fileURLWithPath: out))
                    print("[export] done")
                } catch { print("[export] failed: \(error)") }
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
                if env["MELIES_ANNOTATION_DEMO"] != nil {
                    try? await Task.sleep(for: .seconds(1))
                    if let model = EditorWindowController.shared.session.model {
                        model.annotations = demoAnnotations()
                        model.seek(to: 1.5)
                        model.selectAnnotation(model.annotations[0].id)
                    }
                }
                if env["MELIES_ZOOM_DEMO"] != nil {
                    try? await Task.sleep(for: .seconds(1))
                    EditorWindowController.shared.session.model?.addZoom()
                    if env["MELIES_ZOOM_DEMO"] == "preview" { EditorWindowController.shared.session.model?.selectPoint(nil); EditorWindowController.shared.session.model?.seek(to: 1.5) }
                }
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
