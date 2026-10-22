import AppKit
import SwiftUI

/// Drawing tools in the editor.
enum Tool: Equatable {
    case select, arrow, text, rect, spotlight, blur
}

struct RGBA: Codable, Equatable {
    var r: Double, g: Double, b: Double, a: Double

    static let red = RGBA(r: 1.0, g: 0.23, b: 0.19, a: 1)
    static let orange = RGBA(r: 1.0, g: 0.62, b: 0.04, a: 1)
    static let yellow = RGBA(r: 1.0, g: 0.84, b: 0.04, a: 1)
    static let green = RGBA(r: 0.20, g: 0.78, b: 0.35, a: 1)
    static let blue = RGBA(r: 0.04, g: 0.52, b: 1.0, a: 1)
    static let purple = RGBA(r: 0.69, g: 0.32, b: 0.87, a: 1)
    static let white = RGBA(r: 1, g: 1, b: 1, a: 1)
    static let black = RGBA(r: 0, g: 0, b: 0, a: 1)
    static let palette: [RGBA] = [.red, .orange, .yellow, .green, .blue, .purple, .white, .black]

    var cg: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: a) }
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    init(r: Double, g: Double, b: Double, a: Double) { self.r = r; self.g = g; self.b = b; self.a = a }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .red
        self.init(r: Double(ns.redComponent), g: Double(ns.greenComponent), b: Double(ns.blueComponent), a: Double(ns.alphaComponent))
    }
}

enum AnnotationKind: String, Codable, CaseIterable { case arrow, text, rect, spotlight, blur }
enum ArrowStyle: String, CaseIterable, Codable { case block, line, double }
enum RectStyle: String, CaseIterable, Codable { case rounded, square, soft, solid }
enum FontStyle: String, CaseIterable, Codable { case sans, rounded, serif, mono, hand }
enum TextBox: String, CaseIterable, Codable { case plain, boxed, badge }
enum BlurStyle: String, CaseIterable, Codable { case pixelate, gaussian }

/// An element drawn on the video, visible between `start` and `end` (asset time, seconds).
/// Geometry is normalized in the upright source frame (0...1, top-left origin), so it follows
/// crop and zoom animation. Sizes (`width`) are in units of 1/1000 of the source width.
struct Annotation: Identifiable, Equatable {
    var id = UUID()
    var kind: AnnotationKind
    var start: Double
    var end: Double
    var p1: CGPoint          // arrow tail, rectangle corner, or text anchor (top-left)
    var p2: CGPoint          // arrow head, or opposite rectangle corner
    var color: RGBA
    var width: Double        // line thickness, or font size for text
    var arrow: ArrowStyle
    var rect: RectStyle
    var text: String
    var font: FontStyle
    var bold: Bool
    var box: TextBox
    /// Spotlight and blur: the shape and the effect. `width` is the darkness (%) or the strength.
    var blur: BlurStyle = .pixelate
    /// Motion found by tracking: offsets (normalized, source frame) relative to where the annotation was drawn
    /// at `trackStart`. Empty when the annotation is not tracked. Before `trackStart` it stays where it was drawn.
    var track: [TrackSample] = []
    var trackStart: Double = 0
    /// Set when tracking stopped before the end of the annotation: when, and why.
    var trackLoss: TrackLoss?
}

struct TrackLoss: Equatable {
    var at: Double
    /// True when the object left the frame, false when it was covered or the picture changed.
    var offscreen: Bool
}

struct TrackSample: Equatable {
    var t: Double
    var dx: Double
    var dy: Double
}

extension Annotation {
    /// How far tracking has moved the annotation at time `t` (held at the last sample after the end).
    func offset(at t: Double) -> CGSize {
        guard let first = track.first, let last = track.last else { return .zero }
        if t >= last.t { return CGSize(width: last.dx, height: last.dy) }
        if t <= first.t { return CGSize(width: first.dx, height: first.dy) }
        var low = 0, high = track.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if track[mid].t <= t { low = mid } else { high = mid }
        }
        let a = track[low], b = track[high]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        return CGSize(width: a.dx + (b.dx - a.dx) * f, height: a.dy + (b.dy - a.dy) * f)
    }

    /// The annotation as it is drawn at `t`: moved by its track, if any.
    func moved(at t: Double) -> Annotation {
        let o = offset(at: t)
        guard o != .zero else { return self }
        var copy = self
        copy.p1 = CGPoint(x: p1.x + o.width, y: p1.y + o.height)
        copy.p2 = CGPoint(x: p2.x + o.width, y: p2.y + o.height)
        return copy
    }

    var isTracked: Bool { !track.isEmpty }
}

/// The look used for the next annotation of each kind: it remembers the last choices.
struct AnnotationStyle: Codable, Equatable {
    var color: RGBA
    var width: Double
    var arrow: ArrowStyle = .block
    var rect: RectStyle = .rounded
    var font: FontStyle = .sans
    var bold = true
    var box: TextBox = .plain
    var blur: BlurStyle = .pixelate
}

enum AnnotationStyleStore {
    private static let key = "annotationStyles"

    static func style(for kind: AnnotationKind) -> AnnotationStyle {
        if let data = UserDefaults.standard.data(forKey: key),
           let all = try? JSONDecoder().decode([String: AnnotationStyle].self, from: data),
           let saved = all[kind.rawValue] { return saved }
        switch kind {
        case .arrow: return AnnotationStyle(color: .red, width: 7)
        case .rect: return AnnotationStyle(color: .red, width: 4)
        case .text: return AnnotationStyle(color: .white, width: 30, box: .badge)
        case .spotlight: return AnnotationStyle(color: .black, width: 65)
        case .blur: return AnnotationStyle(color: .black, width: 12, blur: .pixelate)
        }
    }

    static func save(_ style: AnnotationStyle, for kind: AnnotationKind) {
        var all: [String: AnnotationStyle] = [:]
        if let data = UserDefaults.standard.data(forKey: key),
           let existing = try? JSONDecoder().decode([String: AnnotationStyle].self, from: data) { all = existing }
        all[kind.rawValue] = style
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: key) }
    }
}
