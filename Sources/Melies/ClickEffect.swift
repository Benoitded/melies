import CoreGraphics
import Foundation

/// How recorded clicks are drawn: a ring that grows and fades where the mouse was pressed.
struct ClickSet {
    var clicks: [CursorTrack.Click]
    var color: RGBA
    var size: Double   // radius at the end of the animation, in units of 1/1000 of the source width

    static let duration = 0.6

    /// The style chosen in Settings, over the clicks recorded with the video.
    static func current(for track: CursorTrack?) -> ClickSet? {
        guard let clicks = track?.clicks, !clicks.isEmpty else { return nil }
        return ClickSet(clicks: clicks, color: ClickStyleStore.color, size: ClickStyleStore.size)
    }

    func isActive(at t: Double) -> Bool {
        clicks.contains { t >= $0.t && t <= $0.t + Self.duration }
    }
}

enum ClickStyleStore {
    static let presets: [(name: String, color: RGBA)] = [
        ("yellow", .yellow), ("red", .red), ("blue", .blue), ("green", .green), ("white", .white),
    ]

    static var color: RGBA {
        let name = UserDefaults.standard.string(forKey: Pref.clickColor) ?? "yellow"
        return presets.first { $0.name == name }?.color ?? .yellow
    }

    static var size: Double {
        let v = UserDefaults.standard.double(forKey: Pref.clickSize)
        return v > 0 ? v : 36
    }

    /// Show clicks in the editor and in exports (when the video has any).
    static var enabled: Bool { UserDefaults.standard.object(forKey: Pref.showClicks) as? Bool ?? true }
}

extension AnnotationRenderer {
    /// Draws every click that is currently animating (ring + soft disc) in a y-down source-pixel context.
    static func drawClicks(_ set: ClickSet?, at t: Double, in ctx: CGContext, source: CGSize) {
        guard let set else { return }
        let u = unit(source)
        for click in set.clicks where t >= click.t && t <= click.t + ClickSet.duration {
            let p = (t - click.t) / ClickSet.duration            // 0...1
            let ease = 1 - pow(1 - p, 3)                          // fast start, gentle end
            let center = CGPoint(x: click.x * source.width, y: click.y * source.height)
            let radius = CGFloat(set.size) * u * CGFloat(0.3 + 0.7 * ease)
            let alpha = CGFloat(1 - p)
            let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            ctx.saveGState()
            ctx.setFillColor(set.color.cg.copy(alpha: 0.25 * alpha) ?? set.color.cg)
            ctx.fillEllipse(in: disc)
            ctx.setStrokeColor(set.color.cg.copy(alpha: 0.95 * alpha) ?? set.color.cg)
            ctx.setLineWidth(max(u * 3.5 * CGFloat(1 - 0.5 * p), 1))
            ctx.strokeEllipse(in: disc)
            ctx.restoreGState()
        }
    }
}
