import AppKit

private final class SelectorWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

private final class SelectorView: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var onDone: ((CGRect?) -> Void)?
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

    override func mouseUp(with event: NSEvent) {
        current = convert(event.locationInWindow, from: nil)
        let rect = selection
        onDone?((rect?.width ?? 0) >= 40 && (rect?.height ?? 0) >= 40 ? rect : nil)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: onDone?(nil)      // Esc cancels
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
            view.onDone = { rect in
                window.orderOut(nil)
                continuation.resume(returning: rect.map { ($0, screen) })
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
