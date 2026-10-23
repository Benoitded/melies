import AppKit
import AVFoundation
import KeyboardShortcuts
import SwiftUI

/// First-run walkthrough: welcome, what Melies does, the shortcuts, then the permissions.
/// The window itself is Liquid Glass (see `OnboardingWindowController`), so the content stays flat.
struct OnboardingView: View {
    let done: () -> Void

    /// Debug: MELIES_FORCE_MISSING=1 shows the permission step as missing even when it is granted,
    /// MELIES_ONBOARDING_STEP=n opens on that step.
    private static let forceMissing: Bool = {
        #if DEBUG || MELIES_HOOKS
        return ProcessInfo.processInfo.environment["MELIES_FORCE_MISSING"] != nil
        #else
        return false
        #endif
    }()
    /// The walkthrough opens on its last step when the user came back from System Settings: whether the app
    /// restarted by itself or macOS did ("Quit & Reopen"), the permission is in and only the good news is left.
    private static func firstStep() -> Int {
        #if DEBUG || MELIES_HOOKS
        if let n = ProcessInfo.processInfo.environment["MELIES_ONBOARDING_STEP"].flatMap(Int.init) { return n }
        #endif
        return OnboardingPending.isSet && CGPreflightScreenCaptureAccess() ? 3 : 0
    }

    @State private var step = firstStep()
    @State private var allowed = !forceMissing && CGPreflightScreenCaptureAccess()
    @State private var mic = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var openedSettings = false
    @State private var restarting = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let lastStep = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: features
                case 2: shortcuts
                default: permissions
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(step)
            .transition(.opacity)

            if step == lastStep, openedSettings, !allowed {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(restarting ? L("onb.restarting") : L("onb.waiting")).foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.bottom, 10)
                .transition(.opacity)
            }

            Button(action: advance) { Text(primaryLabel).frame(maxWidth: .infinity) }
                .modifier(ProminentButton())
                .controlSize(.extraLarge)
                .disabled(step == lastStep && !allowed)
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 40)
        .padding(.top, 48)
        .padding(.bottom, 26)
        .frame(width: 760, height: OnboardingWindowController.size.height)
        .overlay(alignment: .top) { if step > 0 { dots.padding(.top, 24) } }
        // The window's (empty) toolbar adds a top inset of its own: lay out from the very top instead.
        .ignoresSafeArea(.container, edges: .top)
        .onAppear {
            if OnboardingPending.isSet, allowed { PermissionGuideController.shared.show(ready: true) }
        }
        .onReceive(poll) { _ in
            mic = AVCaptureDevice.authorizationStatus(for: .audio)
            guard !Self.forceMissing else { return }
            allowed = CGPreflightScreenCaptureAccess()
            if allowed { PermissionGuideController.shared.markReady() }
            // Switched on in Settings but this process still says no: a fresh one will say yes, so restart by ourselves.
            if !allowed, openedSettings, !restarting { Task { await restartIfGranted() } }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
        .animation(.easeInOut(duration: 0.25), value: allowed)
        .animation(.easeInOut(duration: 0.25), value: openedSettings)
    }

    private var primaryLabel: String {
        switch step {
        case 0: L("onb.start")
        case lastStep: L("onb.finish")
        default: L("onb.next")
        }
    }

    private func advance() {
        if step < lastStep { step += 1 } else {
            OnboardingPending.clear()
            PermissionGuideController.shared.hide()
            done()
        }
    }

    // MARK: Steps

    private var dots: some View {
        HStack(spacing: 7) {
            ForEach(1...lastStep, id: \.self) { i in
                Capsule()
                    .fill(i == step ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: i == step ? 34 : 9, height: 9)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    private func header(_ title: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 28, weight: .bold))
            Text(sub).font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var welcome: some View {
        VStack(spacing: 6) {
            RecordingFrameDemo()
            Text("Melies").font(.system(size: 40, weight: .bold)).padding(.top, 6)
            Text(L("onb.tagline")).font(.system(size: 19, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.bottom, 24)
    }

    private var features: some View {
        VStack(spacing: 22) {
            header(L("onb.f.title"), L("onb.f.sub"))
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    featureCard("record.circle", L("onb.f1.t"), L("onb.f1.d"))
                    featureCard("plus.magnifyingglass", L("onb.f2.t"), L("onb.f2.d"))
                    featureCard("scribble.variable", L("onb.f3.t"), L("onb.f3.d"))
                }
                HStack(spacing: 14) {
                    featureCard("captions.bubble", L("onb.f4.t"), L("onb.f4.d"))
                    featureCard("rectangle.inset.filled", L("onb.f5.t"), L("onb.f5.d"))
                    featureCard("square.and.arrow.up", L("onb.f6.t"), L("onb.f6.d"))
                }
            }
            .padding(.bottom, 22)
        }
    }

    private func featureCard(_ symbol: String, _ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.primary.opacity(0.06))
                Image(systemName: symbol).font(.system(size: 26, weight: .medium)).foregroundStyle(.blue)
            }
            .frame(height: 56)
            Text(title).font(.system(size: 15, weight: .semibold)).padding(.top, 2)
            Text(text).font(.system(size: 12.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(card)
    }

    private var shortcuts: some View {
        VStack(spacing: 0) {
            header(L("onb.s.title"), L("onb.s.sub"))
            Spacer().frame(height: 24)
            HStack(spacing: 18) {
                shortcutCard("record.circle", L("onb.s1.t"), L("onb.s1.d"), .record)
                shortcutCard("film", L("onb.s2.t"), L("onb.s2.d"), .openEditor)
            }
            .padding(.bottom, 16)
        }
    }

    private func shortcutCard(_ symbol: String, _ title: String, _ text: String, _ name: KeyboardShortcuts.Name) -> some View {
        VStack(spacing: 18) {
            iconTile(symbol, tint: .blue)
            Text(title).font(.system(size: 24, weight: .bold))
            HStack(spacing: 8) {
                ForEach(Array(keycaps(shortcutLabel(name)).enumerated()), id: \.offset) { _, key in
                    Text(key)
                        .font(.system(size: 26, design: .rounded).weight(.medium))
                        .frame(minWidth: 52, minHeight: 52)
                        .padding(.horizontal, key.count > 1 ? 8 : 0)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                                .shadow(color: .black.opacity(0.18), radius: 0, y: 3))
                }
            }
            Text(text)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(card)
    }

    /// "⇧⌘6" -> ["⇧", "⌘", "6"]: one key cap per modifier, then the key itself.
    private func keycaps(_ label: String) -> [String] {
        let modifiers = "⌃⌥⇧⌘"
        let head = label.prefix { modifiers.contains($0) }
        let rest = label.dropFirst(head.count)
        return head.map(String.init) + (rest.isEmpty ? [] : [String(rest)])
    }

    private var permissions: some View {
        VStack(spacing: 0) {
            header(L("onb.p.title"), L("onb.p.sub"))
            Spacer().frame(height: 24)
            HStack(spacing: 18) {
                permissionCard(
                    symbol: "rectangle.dashed.badge.record",
                    title: L("onb.p.screen.t"), tag: L("onb.p.screen.tag"), text: L("onb.p.screen.d"),
                    bullets: [L("onb.p.screen.b1"), L("onb.p.screen.b2"), L("onb.p.screen.b3")],
                    granted: allowed, action: allowScreen, label: L("onb.allow"))
                permissionCard(
                    symbol: "mic.fill",
                    title: L("onb.p.mic.t"), tag: L("onb.p.mic.tag"), text: L("onb.p.mic.d"),
                    bullets: [L("onb.p.mic.b1"), L("onb.p.mic.b2")],
                    granted: mic == .authorized, action: allowMicrophone,
                    label: mic == .notDetermined ? L("onb.allow") : L("onb.open"))
            }
            .padding(.bottom, 16)
        }
    }

    private func permissionCard(symbol: String, title: String, tag: String, text: String, bullets: [String],
                                granted: Bool, action: @escaping () -> Void, label: String) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                iconTile(symbol, tint: .blue)
                Text(title).font(.system(size: 20, weight: .bold)).padding(.top, 2)
                Text(tag).font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                Text(text)
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(bullets, id: \.self) { b in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.tertiary)
                            Text(b).foregroundStyle(.secondary)
                        }
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            }
            Spacer(minLength: 14)
            Button(action: action) {
                Group {
                    if granted {
                        Label(L("onb.granted"), systemImage: "checkmark.circle.fill")
                    } else {
                        Text(label)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .modifier(ProminentButton())
            .controlSize(.large)
            .tint(granted ? .green : .accentColor)
            .allowsHitTesting(!granted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(card)
    }

    private func iconTile(_ symbol: String, tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(tint.gradient)
            .frame(width: 56, height: 56)
            .overlay(Image(systemName: symbol).font(.system(size: 25, weight: .medium)).foregroundStyle(.white))
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.primary.opacity(0.05))
    }

    // MARK: Permissions

    private func allowScreen() {
        OnboardingPending.set()
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        openedSettings = true
        PermissionGuideController.shared.show(ready: false)
    }

    private func allowMicrophone() {
        if mic == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                mic = AVCaptureDevice.authorizationStatus(for: .audio)
            }
        } else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks a fresh copy of the app whether the switch is on now; if so, relaunches into the new state.
    private func restartIfGranted() async {
        guard let executable = Bundle.main.executableURL else { return }
        let granted = await Task.detached { () -> Bool in
            let probe = Process()
            probe.executableURL = executable
            probe.arguments = ["--check-screen-access"]
            guard (try? probe.run()) != nil else { return false }
            probe.waitUntilExit()
            return probe.terminationStatus == 0
        }.value
        guard granted, !restarting else { return }
        restarting = true
        try? await Task.sleep(for: .milliseconds(900)) // let the message be read
        relaunch()
    }

    private func relaunch() {
        // macOS may have restarted us already ("Quit & Reopen" in its own dialog): then the fresh copy is there, just leave.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0 != .current }) {
            NSApp.terminate(nil)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// Remembers that the user went to System Settings from the walkthrough, across the restart that follows.
enum OnboardingPending {
    private static let key = "onboardingPending"
    static var isSet: Bool { UserDefaults.standard.bool(forKey: key) }
    static func set() { UserDefaults.standard.set(true, forKey: key) }
    static func clear() { UserDefaults.standard.removeObject(forKey: key) }
}

/// Liquid Glass prominent button. Glass is not drawn by offscreen snapshots (and blanks the page), so the
/// debug snapshot hook gets a plain prominent button instead.
private struct ProminentButton: ViewModifier {
    private static let flat: Bool = {
        #if DEBUG || MELIES_HOOKS
        return ProcessInfo.processInfo.environment["MELIES_ONBOARDING_SNAPSHOT"] != nil
        #else
        return false
        #endif
    }()

    @ViewBuilder func body(content: Content) -> some View {
        if Self.flat { content.buttonStyle(.borderedProminent) } else { content.buttonStyle(.glassProminent) }
    }
}

/// The app's core gesture: a dashed selection frame, marching, around the icon, with the recording dot.
private struct RecordingFrameDemo: View {
    @State private var on = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.accentColor.opacity(0.07))
                .frame(width: 320, height: 200)
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [8, 6], dashPhase: on ? -28 : 0))
                .frame(width: 320, height: 200)
                .animation(.linear(duration: 1.4).repeatForever(autoreverses: false), value: on)
            ForEach(0..<4, id: \.self) { i in
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                    .offset(x: i % 2 == 0 ? -160 : 160, y: i < 2 ? -100 : 100)
            }
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
            HStack(spacing: 6) {
                Circle().fill(.red).frame(width: 8, height: 8).opacity(on ? 1 : 0.35)
                    .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
                Text("REC").font(.system(size: 11, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .glassEffect(.regular, in: .capsule)
            .offset(x: -118, y: -122)
        }
        .frame(width: 420, height: 260)
        .onAppear { on = true }
    }
}

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    static let size = NSSize(width: 760, height: 560)
    private var window: NSWindow?

    /// Only worth showing at launch while the one required permission is missing,
    /// or right after the restart that follows the switch being turned on.
    static var needed: Bool { !CGPreflightScreenCaptureAccess() || OnboardingPending.isSet }

    func show() {
        // A window that was closed starts again from the welcome, not from where it was left.
        if let w = window, !w.isVisible { window = nil }
        if window == nil {
            let host = NSHostingView(rootView: OnboardingView(done: { [weak self] in self?.window?.orderOut(nil) }))
            host.sizingOptions = [] // the window is exactly the size the view asks for (the toolbar inset must not add to it)

            // The whole window is a Liquid Glass surface.
            let glass = NSGlassEffectView()
            glass.cornerRadius = 0 // the window clips it (see useSharedGlassShape)
            glass.contentView = host

            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.isOpaque = false
            w.backgroundColor = .clear
            w.contentView = glass
            w.useSharedGlassShape()
            w.setContentSize(OnboardingWindowController.size)
            w.center()
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
                MainActor.assumeIsolated {
                    if CGPreflightScreenCaptureAccess() { OnboardingPending.clear() }
                    PermissionGuideController.shared.hide()
                }
            }
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
