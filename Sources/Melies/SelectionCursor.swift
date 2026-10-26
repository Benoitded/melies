import AppKit

/// The cursor of area selection, as in Shottr: a thin cross with a small ring in the middle. The ring frames the
/// exact pixel where the selection will start. White with a dark edge so it reads on any background.
enum SelectionCursor {
    static let crosshairRing: NSCursor = {
        let size: CGFloat = 25 // odd, so the centre is a pixel
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let c = CGPoint(x: rect.midX, y: rect.midY)
            let ring: CGFloat = 4
            let reach = rect.width / 2 - 1.5

            func draw(_ color: NSColor, width: CGFloat) {
                color.setStroke()
                let path = NSBezierPath()
                path.lineWidth = width
                path.lineCapStyle = .round
                // Four arms, from the edge up to the ring.
                path.move(to: CGPoint(x: c.x - reach, y: c.y)); path.line(to: CGPoint(x: c.x - ring, y: c.y))
                path.move(to: CGPoint(x: c.x + ring, y: c.y)); path.line(to: CGPoint(x: c.x + reach, y: c.y))
                path.move(to: CGPoint(x: c.x, y: c.y - reach)); path.line(to: CGPoint(x: c.x, y: c.y - ring))
                path.move(to: CGPoint(x: c.x, y: c.y + ring)); path.line(to: CGPoint(x: c.x, y: c.y + reach))
                path.stroke()
                NSBezierPath(ovalIn: CGRect(x: c.x - ring, y: c.y - ring, width: ring * 2, height: ring * 2)).apply(width: width, color: color)
            }
            draw(NSColor.black.withAlphaComponent(0.55), width: 3)
            draw(.white, width: 1.1)
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: size / 2, y: size / 2))
    }()
}

private extension NSBezierPath {
    func apply(width: CGFloat, color: NSColor) {
        lineWidth = width
        color.setStroke()
        stroke()
    }
}
