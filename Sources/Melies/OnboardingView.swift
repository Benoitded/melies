import AppKit
import KeyboardShortcuts
import SwiftUI

/// First-launch guide: where the app lives, the two permissions, and the shortcuts.
struct OnboardingView: View {
    let done: () -> Void

    @State private var screenAllowed = CGPreflightScreenCaptureAccess()
    @State private var desktopChecked = false
    private let poll = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Bienvenue dans Méliès").font(.system(size: 22, weight: .bold))
                Text("Enregistre une zone de l'écran, rogne, copie un MP4 prêt pour Twitter.")
                    .foregroundStyle(.secondary)
            }

            step(1, "Trouve l'icône",
                 "Méliès vit dans la barre de menu (icône de film), pas dans le Dock. Si elle est cachée par l'encoche, utilise les raccourcis ci-dessous.") {
                EmptyView()
            }

            step(2, "Autorise l'enregistrement de l'écran",
                 "Obligatoire pour filmer. Active Méliès dans la liste, puis relance l'app si macOS le demande.") {
                PermissionDemo(granted: screenAllowed)
                HStack {
                    status(screenAllowed, ok: "Autorisé", ko: "Pas encore autorisé")
                    Spacer()
                    if !screenAllowed {
                        Button("Autoriser") {
                            CGRequestScreenCaptureAccess()
                            open("Privacy_ScreenCapture")
                        }
                    }
                }
            }

            step(3, "Autorise l'accès au Bureau",
                 "Méliès ouvre automatiquement ta dernière vidéo (par défaut sur le Bureau). Tu peux changer de dossier dans les Réglages.") {
                HStack {
                    status(desktopChecked, ok: "Demandé", ko: "À vérifier")
                    Spacer()
                    Button("Vérifier") {
                        _ = try? FileManager.default.contentsOfDirectory(at: LatestRecording.watchedFolder(), includingPropertiesForKeys: nil)
                        desktopChecked = true
                    }
                }
            }

            step(4, "Retiens deux raccourcis", "Modifiables dans les Réglages.") {
                VStack(spacing: 6) {
                    shortcutRow("Enregistrer / arrêter", KeyboardShortcuts.getShortcut(for: .record)?.description ?? "-")
                    shortcutRow("Ouvrir l'éditeur", KeyboardShortcuts.getShortcut(for: .openEditor)?.description ?? "-")
                }
            }

            Text("Pendant un enregistrement, un bouton rouge ■ apparaît dans la barre de menu : un clic l'arrête et ouvre l'éditeur. Dans l'éditeur : I et O pour rogner, ⌘C pour copier le MP4, ⌘S pour l'enregistrer.")
                .font(.callout).foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Réglages") { SettingsWindowController.shared.show() }
                Button("C'est parti") { done() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onReceive(poll) { _ in screenAllowed = CGPreflightScreenCaptureAccess() }
    }

    /// The step the user should do now; earlier ones are done, later ones are dimmed.
    private var currentStep: Int {
        if !screenAllowed { return 2 }
        if !desktopChecked { return 3 }
        return 4
    }

    private func step<Content: View>(_ n: Int, _ title: String, _ detail: String, @ViewBuilder content: () -> Content) -> some View {
        let finished = n < currentStep
        return HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(finished ? Color.green.opacity(0.9) : Color.accentColor.opacity(n == currentStep ? 0.9 : 0.25))
                if finished {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(n)").font(.system(size: 13, weight: .bold))
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                content()
            }
        }
        .opacity(n > currentStep ? 0.45 : 1)
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }

    private func status(_ ok: Bool, ok okText: String, ko koText: String) -> some View {
        Label(ok ? okText : koText, systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundStyle(ok ? Color.green : Color.orange)
            .font(.callout)
    }

    private func shortcutRow(_ label: String, _ keys: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(keys).font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.1)))
        }
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    static var needed: Bool { !UserDefaults.standard.bool(forKey: "onboardingDone") }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Bienvenue"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(done: { [weak self] in
                UserDefaults.standard.set(true, forKey: "onboardingDone")
                self?.window?.orderOut(nil)
            }))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

/// Looping mock of System Settings: a fake cursor moves to the Méliès switch and turns it on.
/// It reacts to the real permission state: once granted, the loop stops on a green "on" switch.
private struct PermissionDemo: View {
    let granted: Bool

    @State private var on = false
    @State private var cursor = CGPoint(x: 330, y: 150)
    @State private var cursorVisible = true
    @State private var ripple = false

    private let rowHeight: CGFloat = 34
    private let target = CGPoint(x: 420, y: 59) // center of the Méliès switch

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                row("Google Chrome", on: true, highlight: false)
                row("Méliès", on: on || granted, highlight: true)
                row("Shottr", on: true, highlight: false)
            }
            .padding(8)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)))

            Circle()
                .stroke(Color.white.opacity(0.9), lineWidth: 2)
                .frame(width: 30, height: 30)
                .scaleEffect(ripple ? 1.3 : 0.4)
                .opacity(ripple ? 0 : 0.0001)
                .position(target)

            Image(systemName: "cursorarrow")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                .position(x: cursor.x + 6, y: cursor.y + 8)
                .opacity(cursorVisible && !granted ? 1 : 0)
        }
        .frame(width: 440, height: 124, alignment: .topLeading)
        .task(id: granted) { await loop() }
    }

    private func row(_ name: String, on: Bool, highlight: Bool) -> some View {
        HStack {
            Image(systemName: highlight ? "film" : "app.fill")
                .frame(width: 20)
                .foregroundStyle(highlight ? Color.accentColor : .secondary)
            Text(name).fontWeight(highlight ? .semibold : .regular)
            Spacer()
            Capsule()
                .fill(on ? (highlight && granted ? Color.green : Color.accentColor) : Color.white.opacity(0.2))
                .frame(width: 38, height: 22)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 18, height: 18).padding(2)
                }
        }
        .padding(.horizontal, 12)
        .frame(height: rowHeight)
        .background(highlight && !granted ? Color.accentColor.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func loop() async {
        if granted { withAnimation(.easeInOut(duration: 0.3)) { on = true }; return }
        while !Task.isCancelled {
            on = false
            cursorVisible = true
            cursor = CGPoint(x: 330, y: 150)
            try? await Task.sleep(for: .milliseconds(700))
            withAnimation(.easeInOut(duration: 1.0)) { cursor = target }
            try? await Task.sleep(for: .milliseconds(1100))
            ripple = false
            withAnimation(.easeOut(duration: 0.45)) { ripple = true }
            withAnimation(.spring(duration: 0.3)) { on = true }
            try? await Task.sleep(for: .milliseconds(1500))
            ripple = false
            withAnimation(.easeIn(duration: 0.25)) { cursorVisible = false }
            try? await Task.sleep(for: .milliseconds(900))
        }
    }
}
