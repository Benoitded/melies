import AppKit
import KeyboardShortcuts
import SwiftUI

/// Shown only while screen recording is not allowed. One job: get the switch turned on.
struct OnboardingView: View {
    let done: () -> Void

    @State private var allowed = CGPreflightScreenCaptureAccess()
    @State private var openedSettings = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 22) {
            if allowed { ready } else { needsPermission }
        }
        .padding(28)
        .frame(width: 440)
        .onReceive(poll) { _ in allowed = CGPreflightScreenCaptureAccess() }
        .animation(.easeInOut(duration: 0.25), value: allowed)
    }

    private var needsPermission: some View {
        VStack(spacing: 18) {
            VStack(spacing: 6) {
                Text(L("onb.title"))
                    .font(.system(size: 20, weight: .semibold))
                Text(L("onb.sub"))
                    .foregroundStyle(.secondary)
            }
            PermissionDemo(granted: allowed)
            VStack(spacing: 8) {
                Button(L("onb.open")) {
                    CGRequestScreenCaptureAccess()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                        NSWorkspace.shared.open(url)
                    }
                    openedSettings = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if openedSettings {
                    HStack(spacing: 6) {
                        Text(L("onb.relaunch_hint")).foregroundStyle(.secondary)
                        Button(L("onb.relaunch")) { relaunch() }.buttonStyle(.link)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private var ready: some View {
        VStack(spacing: 18) {
            Text(L("onb.ready")).font(.system(size: 20, weight: .semibold))
            VStack(spacing: 10) {
                shortcutRow(L("onb.rec_row"), .record)
                shortcutRow(L("onb.editor_row"), .openEditor)
            }
            Button(L("onb.ok")) { done() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func shortcutRow(_ label: String, _ name: KeyboardShortcuts.Name) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(shortcutLabel(name))
                .font(.system(size: 13, design: .rounded).weight(.medium))
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary))
        }
    }

    private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Looping mock of the System Settings list: a cursor moves to the Méliès switch and turns it on.
/// Stops on its own as soon as the real permission is granted.
private struct PermissionDemo: View {
    let granted: Bool

    @State private var on = false
    @State private var cursor = CGPoint(x: 300, y: 130)
    @State private var cursorVisible = true

    private let width: CGFloat = 384
    private let rowHeight: CGFloat = 44
    private var target: CGPoint { CGPoint(x: width - 44, y: rowHeight * 1.5) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                row("Google Chrome", icon: icon(at: "/Applications/Google Chrome.app"), on: .constant(true))
                Divider().padding(.leading, 52)
                row("Méliès", icon: NSApp.applicationIconImage, on: Binding(get: { on || granted }, set: { _ in }))
                Divider().padding(.leading, 52)
                row("Shottr", icon: icon(at: "/Applications/Shottr.app"), on: .constant(true))
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.quaternary.opacity(0.6)))
            .frame(width: width)

            Image(systemName: "cursorarrow")
                .font(.system(size: 20))
                .foregroundStyle(.black, .white)
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                .position(x: cursor.x + 5, y: cursor.y + 8)
                .opacity(cursorVisible && !granted ? 1 : 0)
        }
        .frame(width: width, height: rowHeight * 3)
        .task(id: granted) { await loop() }
    }

    private func row(_ name: String, icon: NSImage?, on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: icon ?? NSImage()).resizable().frame(width: 26, height: 26)
            Text(name)
            Spacer()
            Toggle("", isOn: on).toggleStyle(.switch).labelsHidden().allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
    }

    private func icon(at path: String) -> NSImage? {
        FileManager.default.fileExists(atPath: path) ? NSWorkspace.shared.icon(forFile: path) : nil
    }

    private func loop() async {
        if granted { withAnimation { on = true }; return }
        while !Task.isCancelled {
            on = false
            cursorVisible = true
            cursor = CGPoint(x: 300, y: 130)
            try? await Task.sleep(for: .milliseconds(800))
            withAnimation(.easeInOut(duration: 1.0)) { cursor = target }
            try? await Task.sleep(for: .milliseconds(1250))
            withAnimation(.spring(duration: 0.3)) { on = true }
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeIn(duration: 0.25)) { cursorVisible = false }
            try? await Task.sleep(for: .milliseconds(900))
        }
    }
}

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    /// Only worth showing while the one required permission is missing.
    static var needed: Bool { !CGPreflightScreenCaptureAccess() }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(done: { [weak self] in self?.window?.orderOut(nil) }))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func snapshot(to path: String) {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
}
