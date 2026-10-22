import CoreGraphics
import Foundation

/// How the camera travels to a zoom point.
enum ZoomEase: String, CaseIterable {
    case smooth, snappy, linear, spring

    /// Maps travel progress 0...1 to camera progress (spring slightly overshoots).
    func apply(_ u: Double) -> Double {
        let x = min(max(u, 0), 1)
        switch self {
        case .linear: return x
        case .smooth: return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        case .snappy: return 1 - pow(1 - x, 5)
        case .spring:
            let c1 = 1.3, c3 = c1 + 1
            return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
        }
    }

    var labelKey: String { "ease.\(rawValue)" }
}

/// A camera waypoint. The camera arrives at `scale` / `center` at `time`, after travelling for
/// `transition` seconds from the previous point. `center` is normalized in the base view (the crop).
struct ZoomPoint: Identifiable, Equatable {
    var id = UUID()
    var time: Double
    var scale: Double
    var center: CGPoint
    var transition: Double
    var ease: ZoomEase
}

struct CameraState: Equatable {
    var scale: Double
    var center: CGPoint
}

enum ZoomCamera {
    static let rest = CameraState(scale: 1, center: CGPoint(x: 0.5, y: 0.5))

    /// Keeps the visible region inside the frame.
    static func clampedCenter(_ center: CGPoint, scale: Double) -> CGPoint {
        let half = 0.5 / max(scale, 1)
        return CGPoint(x: min(max(center.x, half), 1 - half), y: min(max(center.y, half), 1 - half))
    }

    /// Camera at time `t`: full view before the first point, holds between points, and
    /// travels (log-scale zoom, eased) during each point's transition.
    static func state(at t: Double, points: [ZoomPoint]) -> CameraState {
        var previous = rest
        var previousTime = -Double.infinity
        for point in points {
            let target = CameraState(scale: point.scale, center: clampedCenter(point.center, scale: point.scale))
            let start = max(point.time - point.transition, previousTime)
            if t <= start { return previous }
            if t < point.time {
                let e = point.ease.apply((t - start) / (point.time - start))
                let scale = exp(log(previous.scale) + (log(target.scale) - log(previous.scale)) * e)
                let center = CGPoint(
                    x: previous.center.x + (target.center.x - previous.center.x) * e,
                    y: previous.center.y + (target.center.y - previous.center.y) * e
                )
                let s = max(scale, 1)
                return CameraState(scale: s, center: clampedCenter(center, scale: s))
            }
            previous = target
            previousTime = point.time
        }
        return previous
    }

    /// The visible region inside `base` (normalized source coordinates).
    static func region(of state: CameraState, in base: CGRect) -> CGRect {
        let w = 1 / state.scale
        return CGRect(
            x: base.minX + (state.center.x - w / 2) * base.width,
            y: base.minY + (state.center.y - w / 2) * base.height,
            width: w * base.width,
            height: w * base.height
        )
    }
}

/// How much the cursor path is smoothed before the zoom camera follows it. Saved between sessions.
enum CursorSmoothing: Int, CaseIterable {
    case off, light, smooth

    /// Time constant of the exponential smoothing, seconds (0 = none).
    var timeConstant: Double { [0, 0.08, 0.22][rawValue] }
    var labelKey: String { ["cursor.smoothing.off", "cursor.smoothing.light", "cursor.smoothing.smooth"][rawValue] }

    static var saved: CursorSmoothing {
        get { CursorSmoothing(rawValue: UserDefaults.standard.object(forKey: Pref.cursorSmoothing) as? Int ?? 1) ?? .light }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Pref.cursorSmoothing) }
    }
}

/// Cursor positions and clicks recorded next to a video, normalized in the recorded frame (top-left origin).
struct CursorTrack {
    struct Sample { var t: Double; var x: Double; var y: Double }
    struct Click { var t: Double; var x: Double; var y: Double }
    var samples: [Sample]
    var clicks: [Click] = []

    private struct Payload: Codable {
        var cursor: [[Double]]
        var clicks: [[Double]]
    }

    static func sidecarURL(for video: URL) -> URL {
        video.deletingPathExtension().appendingPathExtension("cursor.json")
    }

    static func load(for video: URL) -> CursorTrack? {
        // The sidecar travels with the video (a zip, a download): it is not trusted. Bounded size and counts, and
        // values clamped, so a crafted file cannot exhaust memory or make every frame scan a million clicks.
        let url = sidecarURL(for: video)
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
        guard size > 0, size <= 5_000_000, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        var cursor: [[Double]] = []
        var clicks: [[Double]] = []
        if let payload = try? decoder.decode(Payload.self, from: data) {
            cursor = payload.cursor
            clicks = payload.clicks
        } else if let legacy = try? decoder.decode([[Double]].self, from: data) {
            cursor = legacy // first version: only the cursor, as a plain array
        } else {
            return nil
        }
        func unit(_ v: Double) -> Double { min(max(v, 0), 1) }
        func valid(_ row: [Double]) -> Bool { row.count == 3 && row.allSatisfy { $0.isFinite } }
        let samples = cursor.prefix(200_000).filter(valid).map { Sample(t: $0[0], x: unit($0[1]), y: unit($0[2])) }
        let taps = clicks.prefix(5_000).filter(valid).map { Click(t: $0[0], x: unit($0[1]), y: unit($0[2])) }
        return samples.isEmpty && taps.isEmpty ? nil : CursorTrack(samples: samples, clicks: taps)
    }

    func save(for video: URL) {
        func rounded(_ a: Double, _ digits: Double) -> Double { (a * digits).rounded() / digits }
        let payload = Payload(
            cursor: samples.map { [rounded($0.t, 1000), rounded($0.x, 10000), rounded($0.y, 10000)] },
            clicks: clicks.map { [rounded($0.t, 1000), rounded($0.x, 10000), rounded($0.y, 10000)] }
        )
        if let data = try? JSONEncoder().encode(payload) { try? data.write(to: Self.sidecarURL(for: video)) }
    }

    /// The cursor path with the jitter taken out: exponential smoothing with a time constant set by `strength`.
    /// Pure and deterministic. Samples are sorted by time first (stable); the first and last samples keep their
    /// exact position, so the path still starts and ends where the recording did. `.off` returns the track as is.
    func smoothed(strength: CursorSmoothing) -> CursorTrack {
        let tau = strength.timeConstant
        guard tau > 0, samples.count > 2 else { return self }
        let sorted = samples.enumerated()
            .sorted { ($0.element.t, $0.offset) < ($1.element.t, $1.offset) }
            .map(\.element)
            .filter { $0.t.isFinite && $0.x.isFinite && $0.y.isFinite }
        guard sorted.count > 2 else { return self }
        var out = sorted
        var x = sorted[0].x, y = sorted[0].y
        for i in 1..<(sorted.count - 1) {
            let dt = max(sorted[i].t - sorted[i - 1].t, 0)
            let a = 1 - exp(-dt / tau)
            x += (sorted[i].x - x) * a
            y += (sorted[i].y - y) * a
            out[i].x = x
            out[i].y = y
        }
        var copy = self
        copy.samples = out
        return copy
    }

    /// Interpolated cursor position at time `t`.
    func position(at t: Double) -> CGPoint? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return CGPoint(x: first.x, y: first.y) }
        if t >= last.t { return CGPoint(x: last.x, y: last.y) }
        var low = 0, high = samples.count - 1
        while high - low > 1 {
            let mid = (low + high) / 2
            if samples[mid].t <= t { low = mid } else { high = mid }
        }
        let a = samples[low], b = samples[high]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 0
        return CGPoint(x: a.x + (b.x - a.x) * f, y: a.y + (b.y - a.y) * f)
    }
}
