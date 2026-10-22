import AppKit
import SwiftUI

private final class CountdownModel: ObservableObject {
    @Published var remaining = 0
}

private struct CountdownView: View {
    @ObservedObject var model: CountdownModel

    var body: some View {
        ZStack {
            Text("\(model.remaining)")
                .font(.system(size: 76, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .animation(.spring(duration: 0.35), value: model.remaining)
        }
        .frame(width: 150, height: 150)
        .glassEffect(.regular, in: .circle)
    }
}

/// An optional count-down before the recording starts (3, 5 or 10 seconds; 0 = none, the default). It shows in the
/// middle of the area about to be recorded; Esc, or the record shortcut again, cancels.
@MainActor
enum Countdown {
    private static var cancelled = false
    private(set) static var isRunning = false

    static func cancel() { cancelled = true }

    /// Counts down, then returns true. Returns false when it was cancelled.
    static func run(seconds: Int, region: CGRect, screen: NSScreen) async -> Bool {
        guard seconds > 0 else { return true }
        cancelled = false
        isRunning = true
        defer { isRunning = false }

        let model = CountdownModel()
        model.remaining = seconds
        let size: CGFloat = 150
        // `region` is relative to the screen with a top-left origin; windows use bottom-left global coordinates.
        let center = CGPoint(x: screen.frame.minX + region.midX, y: screen.frame.minY + screen.frame.height - region.midY)
        let panel = NSPanel(contentRect: NSRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: CountdownView(model: model))
        panel.orderFrontRegardless()
        defer { panel.orderOut(nil) }

        let escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { Countdown.cancelled = true; return nil }
            return event
        }
        defer { if let escape { NSEvent.removeMonitor(escape) } }

        for second in stride(from: seconds, to: 0, by: -1) {
            model.remaining = second
            // Wait one second in small steps so a cancel is felt at once.
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(100))
                if cancelled { return false }
            }
        }
        panel.orderOut(nil)
        try? await Task.sleep(for: .milliseconds(120)) // let the number disappear before the first captured frame
        return !cancelled
    }
}
