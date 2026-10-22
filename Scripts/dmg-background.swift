// Draws the DMG window background: a flat neutral color and a thin arrow from the app to Applications.
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
NSColor(calibratedRed: 0.94, green: 0.93, blue: 0.91, alpha: 1).setFill()
full.fill()

// A thin grey arrow between the two icons (app at x=180, Applications at x=480, icon centers at y=205 from the top).
let y = CGFloat(height) - 205
NSColor(calibratedWhite: 0.55, alpha: 0.85).setStroke()
let shaft = NSBezierPath()
shaft.lineWidth = 2.5; shaft.lineCapStyle = .round
shaft.move(to: NSPoint(x: 262, y: y)); shaft.line(to: NSPoint(x: 398, y: y))
shaft.stroke()
let head = NSBezierPath()
head.lineWidth = 2.5; head.lineCapStyle = .round; head.lineJoinStyle = .round
head.move(to: NSPoint(x: 382, y: y + 14)); head.line(to: NSPoint(x: 398, y: y)); head.line(to: NSPoint(x: 382, y: y - 14))
head.stroke()

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerY: CGFloat) {
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let s = NSAttributedString(string: text, attributes: attrs)
    let w = s.size().width
    s.draw(at: NSPoint(x: (CGFloat(width) - w) / 2, y: centerY))
}
if CommandLine.arguments.count > 2, !CommandLine.arguments[2].isEmpty {
    draw(CommandLine.arguments[2], size: 12, weight: .regular, color: NSColor(calibratedWhite: 0.42, alpha: 1), centerY: 38)
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
