// Draws the DMG window background: a soft violet gradient, a thin arrow from the app to Applications, a title and an optional small hint.
// Usage: swift Scripts/dmg-background.swift out.png ["small hint line"]      (660x400 pt window, written at 2x)
import AppKit

let width = 660, height = 400
guard CommandLine.arguments.count > 1 else { print("usage: dmg-background.swift out.png"); exit(1) }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * 2, pixelsHigh: height * 2, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: width, height: height) // 144 dpi: sharp on Retina
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let full = NSRect(x: 0, y: 0, width: width, height: height)
NSGradient(colors: [NSColor(calibratedRed: 0.975, green: 0.968, blue: 1.0, alpha: 1), NSColor(calibratedRed: 0.915, green: 0.905, blue: 0.985, alpha: 1)])!
    .draw(in: full, angle: -90)

// A thin grey arrow between the two icons (app at x=180, Applications at x=480, icon centers at y=205 from the top).
let y = CGFloat(height) - 205
// One opaque path for the shaft and the head: two translucent strokes would show a dark spot where they overlap.
NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.93, alpha: 1).setStroke()
let arrow = NSBezierPath()
arrow.lineWidth = 3; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
arrow.move(to: NSPoint(x: 262, y: y)); arrow.line(to: NSPoint(x: 398, y: y))
arrow.move(to: NSPoint(x: 382, y: y + 14)); arrow.line(to: NSPoint(x: 398, y: y)); arrow.line(to: NSPoint(x: 382, y: y - 14))
arrow.stroke()

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerY: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let s = NSAttributedString(string: text, attributes: attrs)
    let w = s.size().width
    s.draw(at: NSPoint(x: (CGFloat(width) - w) / 2, y: centerY))
}
draw("Drag Méliès to Applications", size: 17, weight: .semibold, color: NSColor(calibratedRed: 0.17, green: 0.14, blue: 0.30, alpha: 1), centerY: CGFloat(height) - 70)
if CommandLine.arguments.count > 2, !CommandLine.arguments[2].isEmpty {
    draw(CommandLine.arguments[2], size: 12, weight: .regular, color: NSColor(calibratedRed: 0.42, green: 0.40, blue: 0.55, alpha: 1), centerY: 38)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
