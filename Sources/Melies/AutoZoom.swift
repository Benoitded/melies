import CoreGraphics
import Foundation

/// How close the automatic zoom goes. Saved between sessions.
enum AutoZoomStrength: Int, CaseIterable {
    case subtle, normal, strong

    var scale: Double { [1.5, 2.0, 2.6][rawValue] }
    var labelKey: String { ["zoom.auto.subtle", "zoom.auto.normal", "zoom.auto.strong"][rawValue] }

    static var saved: AutoZoomStrength {
        get { AutoZoomStrength(rawValue: UserDefaults.standard.object(forKey: Pref.autoZoomStrength) as? Int ?? 1) ?? .normal }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Pref.autoZoomStrength) }
    }
}

/// Builds the camera path from the recorded clicks. Pure (no UI, no model), so it can be tested.
///
/// - Clicks that come close together in time share one zoom; a double click counts once.
/// - The zoom level fits the area the clicks cover: a small area zooms in at the chosen strength, clicks spread over
///   most of the screen are left alone (zooming there only makes the picture dizzy).
/// - Inside one zoom the camera stays still while the clicks happen near its centre, and glides to a new centre only
///   when a click would come near the edge of the view.
/// - Between two zooms that follow each other closely, the camera glides from one to the other instead of zooming
///   all the way out and back in.
struct AutoZoom {
    var strength: AutoZoomStrength = .normal
    /// The trimmed range, seconds.
    var range: ClosedRange<Double>
    /// The crop region (normalized in the source), or the whole frame.
    var base = CGRect(x: 0, y: 0, width: 1, height: 1)

    // Timing (seconds) and thresholds.
    var lead = 0.5          // the zoom starts this long before the first click
    var hold = 1.3          // and stays this long after the last one
    var groupGap = 2.2      // clicks closer than this belong to the same zoom
    var glueGap = 1.2       // two zooms closer than this are linked without zooming out
    var minScale = 1.3      // below this, the clicks cover too much of the screen: no zoom
    var margin = 0.10       // room kept around the clicked area

    struct Result {
        var points: [ZoomPoint]
        var zooms: Int
        var clicks: Int
    }

    private struct Tap { var t: Double; var p: CGPoint }

    func generate(from clicks: [CursorTrack.Click]) -> Result {
        let taps = normalized(clicks)
        var groups: [[Tap]] = []
        for tap in taps {
            if let last = groups.last?.last, tap.t - last.t < groupGap { groups[groups.count - 1].append(tap) } else { groups.append([tap]) }
        }

        struct Plan { var points: [ZoomPoint]; var arrive: Double; var out: Double; var scale: Double; var taps: Int }
        var plans: [Plan] = []
        for group in groups {
            guard let first = group.first, let last = group.last else { continue }
            let xs = group.map(\.p.x), ys = group.map(\.p.y)
            let span = max((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
            let fit = 1 / (span + 2 * margin)
            // Spread over most of the screen with several clicks: leave it alone. A lone click always gets a zoom.
            if group.count >= 3, fit < minScale { continue }
            let scale = min(strength.scale, max(fit, minScale))

            let arrive = max(first.t - lead, range.lowerBound + 0.05)
            let out = min(last.t + hold, range.upperBound - 0.05)
            guard out > arrive + 0.4 else { continue }

            // All the clicks fit in one view: frame the middle of them and keep the camera still. Otherwise start on the
            // first click and follow the others.
            let allFit = fit >= scale - 0.0001
            let middle = CGPoint(x: ((xs.min() ?? 0) + (xs.max() ?? 0)) / 2, y: ((ys.min() ?? 0) + (ys.max() ?? 0)) / 2)
            var points = [ZoomPoint(time: arrive, scale: scale, center: center(allFit ? middle : first.p, scale), transition: min(lead, arrive - range.lowerBound + 0.05), ease: .smooth)]
            var centre = points[0].center
            // Stay still while clicks fall in the middle 60% of the view; glide when one nears the edge.
            let safe = 0.5 / scale * 0.6
            for tap in group.dropFirst() where !allFit && (abs(tap.p.x - centre.x) > safe || abs(tap.p.y - centre.y) > safe) {
                let target = self.center(tap.p, scale)
                let travel = hypot(target.x - centre.x, target.y - centre.y)
                let transition = min(max(0.35 + travel, 0.35), 0.9)
                let time = max(tap.t - 0.3, (points.last?.time ?? arrive) + transition * 0.6)
                points.append(ZoomPoint(time: time, scale: scale, center: target, transition: transition, ease: .smooth))
                centre = target
            }
            plans.append(Plan(points: points, arrive: arrive, out: out, scale: scale, taps: group.count))
        }

        // Link zooms that follow each other closely: no zoom-out between them.
        var all: [ZoomPoint] = []
        for (i, plan) in plans.enumerated() {
            var points = plan.points
            if let previous = plans[safe: i - 1], plan.arrive - previous.out < glueGap, let from = all.last {
                // The previous zoom did not zoom out: this one's first point becomes a glide from where the camera is.
                let travel = hypot(points[0].center.x - from.center.x, points[0].center.y - from.center.y)
                points[0].transition = min(max(0.5 + travel, 0.6), 1.0)
                points[0].time = max(plan.arrive, from.time + 0.3)
            }
            all += points
            let next = plans[safe: i + 1]
            let glued = next.map { $0.arrive - plan.out < glueGap } ?? false
            if !glued {
                all.append(ZoomPoint(time: plan.out, scale: 1, center: CGPoint(x: 0.5, y: 0.5), transition: 0.7, ease: .smooth))
            }
        }
        return Result(points: all.sorted { $0.time < $1.time }, zooms: plans.count, clicks: plans.reduce(0) { $0 + $1.taps })
    }

    /// Clicks inside the range and the crop, in crop-relative coordinates; a double click is kept once.
    private func normalized(_ clicks: [CursorTrack.Click]) -> [Tap] {
        var result: [Tap] = []
        for c in clicks.sorted(by: { $0.t < $1.t }) where range.contains(c.t) {
            let p = CGPoint(x: (c.x - base.minX) / base.width, y: (c.y - base.minY) / base.height)
            guard (-0.02...1.02).contains(p.x), (-0.02...1.02).contains(p.y) else { continue }
            if let last = result.last, c.t - last.t < 0.25, hypot(p.x - last.p.x, p.y - last.p.y) < 0.03 { continue }
            result.append(Tap(t: c.t, p: CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))))
        }
        return result
    }

    private func center(_ p: CGPoint, _ scale: Double) -> CGPoint { ZoomCamera.clampedCenter(p, scale: scale) }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
