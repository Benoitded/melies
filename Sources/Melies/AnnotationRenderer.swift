import AppKit
import CoreGraphics
import CoreImage

/// Draws annotations with Core Graphics. The context must map source pixels to the target with a
/// top-left origin (y down). The editor preview and the export share this, so they always agree.
enum AnnotationRenderer {
    static let fade = 0.15

    static func unit(_ source: CGSize) -> CGFloat { max(source.width, 1) / 1000 }

    static func isVisible(_ a: Annotation, at t: Double) -> Bool { t >= a.start - 0.0001 && t <= a.end + 0.0001 }

    /// Fades in and out over `fade` seconds.
    static func opacity(_ a: Annotation, at t: Double) -> Double {
        let span = max(a.end - a.start, 0.001)
        let f = min(fade, span / 2)
        return max(0, min(1, (t - a.start) / f, (a.end - t) / f))
    }

    static func hasVisible(_ list: [Annotation], at t: Double) -> Bool {
        list.contains { isVisible($0, at: t) }
    }

    // MARK: Geometry

    static func point(_ n: CGPoint, _ source: CGSize) -> CGPoint { CGPoint(x: n.x * source.width, y: n.y * source.height) }

    static func normalizedRect(_ a: Annotation, _ source: CGSize) -> CGRect {
        let p = point(a.p1, source), q = point(a.p2, source)
        return CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y))
    }

    static func nsFont(_ a: Annotation, source: CGSize) -> NSFont {
        let size = CGFloat(a.width) * unit(source)
        let weight: NSFont.Weight = a.bold ? .bold : .medium
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        func design(_ d: NSFontDescriptor.SystemDesign) -> NSFont {
            base.fontDescriptor.withDesign(d).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
        switch a.font {
        case .sans: return base
        case .rounded: return design(.rounded)
        case .serif: return design(.serif)
        case .mono: return design(.monospaced)
        case .hand: return NSFont(name: a.bold ? "Noteworthy-Bold" : "Noteworthy-Light", size: size) ?? base
        }
    }

    private static func textPadding(_ a: Annotation, _ source: CGSize) -> CGSize {
        let size = CGFloat(a.width) * unit(source)
        return a.box == .plain ? .zero : CGSize(width: size * 0.5, height: size * 0.28)
    }

    private static func attributed(_ a: Annotation, _ source: CGSize, color: CGColor) -> NSAttributedString {
        NSAttributedString(string: a.text.isEmpty ? " " : a.text, attributes: [
            .font: nsFont(a, source: source),
            .foregroundColor: NSColor(cgColor: color) ?? .white,
        ])
    }

    /// Bounding box in source pixels.
    static func bounds(of a: Annotation, source: CGSize) -> CGRect {
        let u = unit(source)
        switch a.kind {
        case .rect:
            return normalizedRect(a, source)
        case .arrow:
            let p = point(a.p1, source), q = point(a.p2, source)
            let pad = CGFloat(a.width) * u * 2.4
            return CGRect(x: min(p.x, q.x), y: min(p.y, q.y), width: abs(p.x - q.x), height: abs(p.y - q.y)).insetBy(dx: -pad, dy: -pad)
        case .text:
            let size = attributed(a, source, color: a.color.cg).boundingRect(with: CGSize(width: 10000, height: 10000), options: [.usesLineFragmentOrigin]).size
            let pad = textPadding(a, source)
            let origin = point(a.p1, source)
            return CGRect(x: origin.x, y: origin.y, width: ceil(size.width) + pad.width * 2, height: ceil(size.height) + pad.height * 2)
        }
    }

    // MARK: Drawing

    /// `animated: false` skips the fade, so a paused editor shows annotations fully (a new annotation
    /// starts exactly at the playhead, where the fade would make it invisible).
    static func draw(_ list: [Annotation], at t: Double, in ctx: CGContext, source: CGSize, animated: Bool = true) {
        for a in list where isVisible(a, at: t) {
            ctx.saveGState()
            ctx.setAlpha(animated ? CGFloat(opacity(a, at: t)) : 1)
            switch a.kind {
            case .arrow: drawArrow(a, ctx, source)
            case .rect: drawRect(a, ctx, source)
            case .text: drawText(a, ctx, source)
            }
            ctx.restoreGState()
        }
    }

    private static func shadow(_ ctx: CGContext, _ u: CGFloat) {
        ctx.setShadow(offset: CGSize(width: 0, height: u * 1.2), blur: u * 3, color: CGColor(gray: 0, alpha: 0.35))
    }

    private static func drawArrow(_ a: Annotation, _ ctx: CGContext, _ source: CGSize) {
        let u = unit(source)
        let p = point(a.p1, source), q = point(a.p2, source)
        let w = CGFloat(a.width) * u
        let dx = q.x - p.x, dy = q.y - p.y
        let length = hypot(dx, dy)
        guard length > 1 else { return }
        let dir = CGPoint(x: dx / length, y: dy / length)
        let normal = CGPoint(x: -dir.y, y: dir.x)
        func at(_ base: CGPoint, _ along: CGFloat, _ across: CGFloat) -> CGPoint {
            CGPoint(x: base.x + dir.x * along + normal.x * across, y: base.y + dir.y * along + normal.y * across)
        }
        shadow(ctx, u)
        ctx.setFillColor(a.color.cg)
        ctx.setStrokeColor(a.color.cg)

        switch a.arrow {
        case .block:
            let head = min(w * 4.4, length * 0.75)
            let neck = at(q, -head, 0)
            let path = CGMutablePath()
            path.move(to: at(p, 0, w * 0.28))
            path.addLine(to: at(neck, 0, w * 0.5))
            path.addLine(to: at(neck, 0, w * 2.2))
            path.addLine(to: q)
            path.addLine(to: at(neck, 0, -w * 2.2))
            path.addLine(to: at(neck, 0, -w * 0.5))
            path.addLine(to: at(p, 0, -w * 0.28))
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        case .line, .double:
            let stroke = max(w * 0.6, 1.5 * u)
            ctx.setLineWidth(stroke)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            let head = min(w * 3.6, length * 0.6)
            let angle: CGFloat = 0.5
            func barbs(at tip: CGPoint, direction d: CGFloat) {
                for side: CGFloat in [-1, 1] {
                    let back = CGPoint(
                        x: tip.x - d * head * (dir.x * cos(angle) - side * dir.y * sin(angle)),
                        y: tip.y - d * head * (dir.y * cos(angle) + side * dir.x * sin(angle))
                    )
                    ctx.move(to: tip)
                    ctx.addLine(to: back)
                }
            }
            ctx.move(to: p)
            ctx.addLine(to: q)
            barbs(at: q, direction: 1)
            if a.arrow == .double { barbs(at: p, direction: -1) }
            ctx.strokePath()
        }
    }

    private static func drawRect(_ a: Annotation, _ ctx: CGContext, _ source: CGSize) {
        let u = unit(source)
        let r = normalizedRect(a, source)
        guard r.width > 1, r.height > 1 else { return }
        let stroke = CGFloat(a.width) * u
        let radius = a.rect == .square ? 0 : min(min(r.width, r.height) * 0.2, 14 * u)
        let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
        shadow(ctx, u)
        switch a.rect {
        case .rounded, .square:
            ctx.setStrokeColor(a.color.cg)
            ctx.setLineWidth(stroke)
            ctx.addPath(path)
            ctx.strokePath()
        case .soft:
            ctx.setFillColor(a.color.cg.copy(alpha: 0.2) ?? a.color.cg)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0)
            ctx.setStrokeColor(a.color.cg)
            ctx.setLineWidth(stroke)
            ctx.addPath(path)
            ctx.strokePath()
        case .solid:
            ctx.setFillColor(a.color.cg.copy(alpha: 0.85) ?? a.color.cg)
            ctx.addPath(path)
            ctx.fillPath()
        }
    }

    private static func drawText(_ a: Annotation, _ ctx: CGContext, _ source: CGSize) {
        let u = unit(source)
        let box = bounds(of: a, source: source)
        let pad = textPadding(a, source)
        let size = CGFloat(a.width) * u
        let textColor: CGColor
        switch a.box {
        case .badge:
            let pill = CGPath(roundedRect: box, cornerWidth: size * 0.38, cornerHeight: size * 0.38, transform: nil)
            shadow(ctx, u)
            ctx.setFillColor(a.color.cg)
            ctx.addPath(pill)
            ctx.fillPath()
            ctx.setShadow(offset: .zero, blur: 0)
            textColor = a.color.luminance > 0.6 ? CGColor(gray: 0, alpha: 1) : CGColor(gray: 1, alpha: 1)
        case .boxed:
            let outline = CGPath(roundedRect: box, cornerWidth: size * 0.3, cornerHeight: size * 0.3, transform: nil)
            ctx.setStrokeColor(a.color.cg)
            ctx.setLineWidth(max(size * 0.1, 1.5 * u))
            ctx.addPath(outline)
            ctx.strokePath()
            textColor = a.color.cg
            shadow(ctx, u)
        case .plain:
            textColor = a.color.cg
            shadow(ctx, u)
        }
        let text = attributed(a, source, color: textColor)
        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = gc
        text.draw(with: CGRect(x: box.minX + pad.width, y: box.minY + pad.height, width: box.width, height: box.height), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
    }

    // MARK: Hit testing (source pixels)

    static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    /// True if a click at `p` (source pixels) should select `a`. `slop` is extra reach in source pixels.
    static func hit(_ a: Annotation, at p: CGPoint, source: CGSize, slop: CGFloat) -> Bool {
        let u = unit(source)
        switch a.kind {
        case .arrow:
            let reach = max(CGFloat(a.width) * u * 1.4, slop)
            return distance(from: p, toSegment: point(a.p1, source), point(a.p2, source)) <= reach
        case .text:
            return bounds(of: a, source: source).insetBy(dx: -slop / 2, dy: -slop / 2).contains(p)
        case .rect:
            let r = normalizedRect(a, source)
            if a.rect == .soft || a.rect == .solid { return r.insetBy(dx: -slop, dy: -slop).contains(p) }
            let outer = r.insetBy(dx: -slop, dy: -slop)
            let inner = r.insetBy(dx: slop, dy: slop)
            return outer.contains(p) && !(inner.width > 0 && inner.height > 0 && inner.contains(p))
        }
    }
}

extension AnnotationRenderer {
    /// Overlay for the export: annotations drawn at output resolution, ready to composite over the frame.
    /// `region` is the visible part of the source (source pixels), `content` where it lands in the canvas.
    static func overlay(_ list: [Annotation], at t: Double, source: CGSize, region: CGRect, content: CGRect, canvas: CGSize) -> CIImage? {
        guard hasVisible(list, at: t) else { return nil }
        let width = Int(canvas.width), height = Int(canvas.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1) // y down, like the preview
        ctx.clip(to: content)
        let k = content.width / region.width
        ctx.translateBy(x: content.minX, y: content.minY)
        ctx.scaleBy(x: k, y: k)
        ctx.translateBy(x: -region.minX, y: -region.minY)
        draw(list, at: t, in: ctx, source: source)
        guard let image = ctx.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }
}
