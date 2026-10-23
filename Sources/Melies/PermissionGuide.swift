import AppKit
import SwiftUI

/// Floating helper that follows the System Settings window while the Screen Recording list is open:
/// the Melies icon can be dragged straight into the list, or the switch flipped by hand.
@MainActor
final class PermissionGuideController {
    static let shared = PermissionGuideController()

    private var panel: NSPanel?
    private var timer: Timer?
    static let size = NSSize(width: 520, height: 92)
    private var size: NSSize { Self.size }

    private let model = GuideModel()
    private var lastSeen = Date()

    func show(ready: Bool) {
        model.ready = ready
        lastSeen = Date()
        if panel == nil { panel = makePanel() }
        guard timer == nil else { return }
        // Settings takes a moment to open: the panel appears as soon as its window does.
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// The switch is on: the same panel turns into a "you're set" message, if it is open.
    func markReady() {
        if timer != nil { model.ready = true }
    }

    /// Debug: where the panel is right now.
    var debugFrame: NSRect? { panel?.isVisible == true ? panel?.frame : nil }

    func hide() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let host = FirstMouseHostingView(rootView: PermissionGuideView(model: model, close: { [weak self] in self?.hide() }))
        host.sizingOptions = [] // the panel keeps the size set below, whatever the content asks for
        let glass = NSGlassEffectView()
        glass.cornerRadius = 26
        glass.contentView = host

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .floating
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        p.contentView = glass
        return p
    }

    /// Keeps the panel centered under the Settings window (over its bottom edge when the screen has no room below).
    private func follow() {
        guard let panel else { return }
        guard let settings = Self.settingsWindowFrame() else {
            panel.orderOut(nil)
            // Done and Settings closed: nothing left to say, stop polling.
            if model.ready, Date().timeIntervalSince(lastSeen) > 4 { hide() }
            return
        }
        lastSeen = Date()
        let screen = NSScreen.screens.first { $0.frame.intersects(settings) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? settings
        var origin = NSPoint(x: settings.midX - size.width / 2, y: settings.minY - size.height - 10)
        if origin.y < visible.minY + 8 { origin.y = settings.minY + 16 }
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Frame of the frontmost on-screen System Settings window, in AppKit coordinates. Needs no permission:
    /// owner and bounds are public, only window titles are protected.
    private static func settingsWindowFrame() -> NSRect? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systempreferences").first?.processIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let primary = NSScreen.screens.first else { return nil }
        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? Int32) == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  bounds.width > 400, bounds.height > 300 else { continue }
            return NSRect(x: bounds.minX, y: primary.frame.height - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        return nil
    }
}

/// A click on the panel must reach it at once, even while another app is in front.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
private final class GuideModel: ObservableObject {
    @Published var ready = false
}

private struct PermissionGuideView: View {
    @ObservedObject var model: GuideModel
    let close: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            if model.ready {
                AppIconFrame()
            } else {
                AppIconFrame().onDrag { NSItemProvider(object: Bundle.main.bundleURL as NSURL) }
                    .help(L("onb.guide.title"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(L(model.ready ? "onb.guide.ready.title" : "onb.guide.title")).font(.system(size: 15, weight: .semibold))
                Text(L(model.ready ? "onb.guide.ready.sub" : "onb.guide.sub"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if model.ready {
                Button(action: close) { Label(L("onb.guide.ready.close"), systemImage: "checkmark") }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
                    .controlSize(.large)
            } else {
                Button(L("onb.guide.skip"), action: close)
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: model.ready)
        .padding(.horizontal, 18)
        .frame(width: PermissionGuideController.size.width, height: PermissionGuideController.size.height)
    }
}

/// The app's icon in a dashed frame (draggable while the permission is missing: it hands System Settings the .app, as Finder would).
private struct AppIconFrame: View {
    var body: some View {
        Image(nsImage: NSApp.applicationIconImage)
            .resizable()
            .frame(width: 48, height: 48)
            .padding(10)
            .accessibilityLabel(Text("Melies"))
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            )
    }
}
