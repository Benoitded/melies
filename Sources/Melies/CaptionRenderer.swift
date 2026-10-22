import AppKit
import CoreGraphics
import CoreImage

/// Draws captions with Core Graphics, in the picture area (`area`, y down). Captions live in canvas space, above the
/// zoomed video: they do not move with the zoom camera or the crop, so they stay readable. The editor preview and the
/// export call the same `draw`, so they agree.
enum CaptionRenderer {
    static func draw(_ text: String, style: CaptionStyle, in ctx: CGContext, area: CGRect) {
        guard !text.isEmpty, area.width > 4, area.height > 4 else { return }
        let size = max(area.width * CGFloat(style.size.factor), 6)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: .semibold),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let maxWidth = area.width * 0.9
        let measured = string.boundingRect(with: CGSize(width: maxWidth - size, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin]).size
        let textW = ceil(measured.width), textH = ceil(measured.height)
        let padX = size * 0.5, padY = size * 0.28
        let boxW = textW + padX * 2, boxH = textH + padY * 2
        let margin = area.height * 0.06
        let boxX = area.midX - boxW / 2
        let boxY = style.position == .bottom ? area.maxY - margin - boxH : area.minY + margin
        let box = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)

        ctx.saveGState()
        if style.background {
            ctx.setFillColor(CGColor(gray: 0, alpha: 0.68))
            ctx.addPath(CGPath(roundedRect: box, cornerWidth: size * 0.4, cornerHeight: size * 0.4, transform: nil))
            ctx.fillPath()
        } else {
            ctx.setShadow(offset: CGSize(width: 0, height: size * 0.05), blur: size * 0.25, color: CGColor(gray: 0, alpha: 0.9))
        }
        let graphics = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphics
        string.draw(with: CGRect(x: box.minX + padX, y: box.minY + padY, width: textW, height: textH), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        ctx.restoreGState()
    }

    /// Export: the caption shown at `t`, drawn at output resolution inside the picture area `content`, ready to composite.
    static func overlay(_ plan: CaptionPlan, at t: Double, content: CGRect, canvas: CGSize) -> CIImage? {
        guard let caption = CaptionLayout.visible(plan.captions, at: t) else { return nil }
        let width = Int(canvas.width), height = Int(canvas.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.translateBy(x: 0, y: canvas.height)
        ctx.scaleBy(x: 1, y: -1) // y down, like the preview
        ctx.clip(to: content)
        draw(caption.text, style: plan.style, in: ctx, area: content)
        guard let image = ctx.makeImage() else { return nil }
        return CIImage(cgImage: image)
    }
}
