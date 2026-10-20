import AppKit

private final class DimView: NSView {
    override var isFlipped: Bool { true }
    var hole: CGRect = .zero

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        dim.append(NSBezierPath(rect: hole))
        dim.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.45).setFill()
        dim.fill()

        // Thin outline just outside the recorded area, so it never touches the captured pixels.
        NSColor.white.withAlphaComponent(0.85).setStroke()
        let outline = NSBezierPath(rect: hole.insetBy(dx: -1.5, dy: -1.5))
        outline.lineWidth = 1.5
        outline.stroke()
    }
}

/// Dims everything except the region being recorded. Click-through, and excluded from the capture.
@MainActor
final class RecordingOverlay {
    private let window: NSWindow

    init(screen: NSScreen, region: CGRect) {
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = .floating // below the menu bar, so the red stop button stays bright
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.sharingType = .none

        let view = DimView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.hole = region
        window.contentView = view
        window.orderFrontRegardless()
    }

    func close() { window.orderOut(nil) }
}
