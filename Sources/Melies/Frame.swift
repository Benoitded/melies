import AppKit
import CoreImage
import SwiftUI

/// The picture framed on a colored background: margins, rounded corners, shadow.
/// One style for the whole app (like the export settings): the preview and the export read the same value.
struct FrameStyle: Codable, Equatable {
    var enabled = false
    /// Margin around the picture, as a fraction of the picture width.
    var padding = 0.08
    /// Corner radius, as a fraction of the picture width.
    var radius = 0.018
    /// Shadow strength, 0...1.
    var shadow = 0.55
    var preset = "aurora"

    static let paddingRange = 0.02...0.25
    static let radiusRange = 0.0...0.06

    static let key = "frameStyle"

    static func load() -> FrameStyle {
        guard let data = UserDefaults.standard.data(forKey: key), let style = try? JSONDecoder().decode(FrameStyle.self, from: data) else { return FrameStyle() }
        return style
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    var fill: FramePreset { FramePreset.all.first { $0.id == preset } ?? FramePreset.all[0] }
}

/// A background: a two-color gradient (top-left to bottom-right) or a solid color (both colors equal).
struct FramePreset: Identifiable {
    let id: String
    let from: RGBA
    let to: RGBA

    private static func hex(_ value: UInt32) -> RGBA {
        RGBA(r: Double((value >> 16) & 0xFF) / 255, g: Double((value >> 8) & 0xFF) / 255, b: Double(value & 0xFF) / 255, a: 1)
    }

    private static func gradient(_ id: String, _ a: UInt32, _ b: UInt32) -> FramePreset { FramePreset(id: id, from: hex(a), to: hex(b)) }
    private static func solid(_ id: String, _ a: UInt32) -> FramePreset { FramePreset(id: id, from: hex(a), to: hex(a)) }

    static let all: [FramePreset] = [
        gradient("aurora", 0x6A5AE0, 0x26C6DA),
        gradient("sunset", 0xFF9A6B, 0xE0407B),
        gradient("ocean", 0x2193B0, 0x6DD5ED),
        gradient("mint", 0x43C6AC, 0xCFF5A5),
        gradient("lavender", 0xB06CF2, 0xFA8BC8),
        gradient("night", 0x0F2027, 0x2C5364),
        gradient("graphite", 0x232526, 0x5B5F63),
        gradient("snow", 0xF8FAFC, 0xBFCBE0),
        solid("white", 0xFFFFFF),
        solid("gray", 0xE6E6EA),
        solid("black", 0x000000),
    ]

    var swiftUI: LinearGradient {
        LinearGradient(colors: [from.color, to.color], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The two static layers of a framed export, drawn once per export: the background with the shadow, and the
/// mask (the rounded picture area). Both are canvas-sized, Core Image coordinates (origin bottom left).
struct FrameLayers {
    let backdrop: CIImage
    let mask: CIImage
    /// Where the picture sits, Core Image coordinates.
    let contentCI: CGRect

    init(style: FrameStyle, canvas: CGSize, content: CGRect) {
        let w = Int(canvas.width), h = Int(canvas.height)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        contentCI = CGRect(x: content.minX, y: canvas.height - content.maxY, width: content.width, height: content.height)
        let radius = min(CGFloat(style.radius) * content.width, min(content.width, content.height) / 2)
        let shape = CGPath(roundedRect: contentCI, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Backdrop: gradient, then the shadow of the picture shape (the picture itself covers the shape).
        let back = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        let fill = style.fill
        let colors = [fill.from.cg, fill.to.cg] as CFArray
        if let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]) {
            back.drawLinearGradient(gradient, start: CGPoint(x: 0, y: canvas.height), end: CGPoint(x: canvas.width, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        if style.shadow > 0.01 {
            let blur = CGFloat(style.shadow) * content.width * 0.05
            back.saveGState()
            back.setShadow(offset: CGSize(width: 0, height: -blur * 0.45), blur: blur, color: CGColor(gray: 0, alpha: 0.55 * CGFloat(style.shadow) + 0.1))
            back.addPath(shape)
            back.setFillColor(CGColor(gray: 0, alpha: 1))
            back.fillPath()
            back.restoreGState()
        }
        backdrop = CIImage(cgImage: back.makeImage()!)

        // Mask: opaque inside the rounded picture area.
        let maskContext = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
        maskContext.addPath(shape)
        maskContext.setFillColor(CGColor(gray: 1, alpha: 1))
        maskContext.fillPath()
        mask = CIImage(cgImage: maskContext.makeImage()!)
    }
}
