import AppKit

private final class SelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectorView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var onDone: ((CGRect?) -> Void)?
    private var finished = false
    private var start: CGPoint?
    private var current: CGPoint?
    private var lastPoint: CGPoint?
    /// While Space is held, dragging moves the whole rectangle instead of resizing it.
    private var spaceHeld = false {
        didSet { window?.invalidateCursorRects(for: self) }
    }

    private var selection: CGRect? {
        guard let start, let current else { return nil }
        return CGRect(
            x: min(start.x, current.x), y: min(start.y, current.y),
            width: abs(start.x - current.x), height: abs(start.y - current.y)
        )
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: spaceHeld ? .closedHand : SelectionCursor.crosshairRing)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.32).setFill()
        bounds.fill()
        guard let rect = selection else { return }
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: rect)
        border.lineWidth = 1.5
        border.stroke()

        let label = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        let pill = NSRect(x: rect.minX, y: max(rect.minY - size.height - 12, 4), width: size.width + 14, height: size.height + 6)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 8, yRadius: 8).fill()
        label.draw(at: NSPoint(x: pill.minX + 7, y: pill.minY + 3), withAttributes: attrs)
    }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        current = start
        lastPoint = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        defer { lastPoint = point; needsDisplay = true }

        guard spaceHeld, let last = lastPoint, let rect = selection, let s = start, let c = current else {
            current = point
            return
        }
        // Move the rectangle by the mouse delta, keeping it fully on screen.
        var dx = point.x - last.x
        var dy = point.y - last.y
        dx = min(max(dx, -rect.minX), bounds.maxX - rect.maxX)
        dy = min(max(dy, -rect.minY), bounds.maxY - rect.maxY)
        start = CGPoint(x: s.x + dx, y: s.y + dy)
        current = CGPoint(x: c.x + dx, y: c.y + dy)
    }

    /// Reports the result once, whatever happens first (mouse up, Esc, the window losing focus).
    func finish(_ rect: CGRect?) {
        guard !finished else { return }
        finished = true
        onDone?(rect)
    }

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        let rect = selection
        let bigEnough = (rect?.width ?? 0) >= 40 && (rect?.height ?? 0) >= 40
        // A real drag that is too small says so; a plain click (nothing dragged) just cancels.
        if !bigEnough, (rect?.width ?? 0) > 4 || (rect?.height ?? 0) > 4 { Toast.show(L("toast.toosmall")) }
        finish(bigEnough ? rect : nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: finish(nil)       // Esc cancels
        case 49: spaceHeld = true  // Space moves the selection
        default: break
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { spaceHeld = false }
    }
}

/// Full-screen overlay to drag a capture rectangle. Returns display-local points (top-left origin).
@MainActor
enum RegionSelector {
    static func select() async -> (rect: CGRect, screen: NSScreen)? {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return nil }

        return await withCheckedContinuation { continuation in
            let window = SelectorWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isReleasedWhenClosed = false

            let view = SelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
            // If the selector loses focus (Cmd+Tab, a Space switch) nothing else would end it: cancel, so the app
            // is never left waiting for a selection that cannot come.
            var focusLoss: NSObjectProtocol?
            view.onDone = { rect in
                if let focusLoss { NotificationCenter.default.removeObserver(focusLoss) }
                window.orderOut(nil)
                continuation.resume(returning: rect.map { ($0, screen) })
            }
            focusLoss = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak view] _ in
                view?.finish(nil)
            }
            window.contentView = view
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)
            // The cross-and-ring is there from the first moment, before any click or mouse move.
            window.invalidateCursorRects(for: view)
            SelectionCursor.crosshairRing.set()
        }
    }
}
