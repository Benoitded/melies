import SwiftUI

/// Lane under the timeline: the zoom level over time as a curve, with a diamond for each waypoint.
/// The curve shows the dynamics at a glance (a long ramp is a slow zoom, a steep one is a fast zoom).
/// Drag a diamond to retime it, click it to edit it.
struct ZoomLane: View {
    @ObservedObject var model: EditorModel

    private let handleWidth: CGFloat = 14 // must match RangeSlider so both lanes line up
    private let height: CGFloat = 42
    private let space = "zoomlane"

    @State private var grab: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - handleWidth * 2, 1)
            let total = max(model.duration, 0.001)
            let x = { (t: Double) -> CGFloat in handleWidth + usable * CGFloat(t / total) }
            let time = { (x: CGFloat) -> Double in Double((x - handleWidth) / usable) * total }

            let top: CGFloat = 8, bottom = height - 8
            let maxScale = max(model.zoomPoints.map(\.scale).max() ?? 2, 2)
            let y = { (scale: Double) -> CGFloat in bottom - CGFloat(log(scale) / log(maxScale)) * (bottom - top) }

            ZStack(alignment: .topLeading) {
                // Baseline: no zoom.
                Path { p in
                    p.move(to: CGPoint(x: handleWidth, y: bottom))
                    p.addLine(to: CGPoint(x: handleWidth + usable, y: bottom))
                }
                .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                .allowsHitTesting(false)

                if model.zoomPoints.isEmpty {
                    Text(L("zoom.hint"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .offset(x: handleWidth + 4, y: bottom - 20)
                        .allowsHitTesting(false)
                } else {
                    let samples = 160
                    let curve = Path { p in
                        for i in 0...samples {
                            let t = total * Double(i) / Double(samples)
                            let scale = ZoomCamera.state(at: t, points: model.zoomPoints).scale
                            let point = CGPoint(x: x(t), y: y(scale))
                            if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
                        }
                    }
                    Path { p in
                        p.addPath(curve)
                        p.addLine(to: CGPoint(x: x(total), y: bottom))
                        p.addLine(to: CGPoint(x: x(0), y: bottom))
                        p.closeSubpath()
                    }
                    .fill(Color.accentColor.opacity(0.16))
                    .allowsHitTesting(false)
                    curve
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                }

                // Playhead, continuing the one in the frame strip.
                Rectangle().fill(Color.primary.opacity(0.4))
                    .frame(width: 1, height: height)
                    .offset(x: x(model.current))
                    .allowsHitTesting(false)

                ForEach(model.zoomPoints) { point in
                    let selected = point.id == model.selectedPointID
                    Rectangle()
                        .fill(selected ? Color.accentColor : Color.white)
                        .overlay(Rectangle().stroke(selected ? Color.white : Color.black.opacity(0.45), lineWidth: 1.2))
                        .frame(width: selected ? 12 : 10, height: selected ? 12 : 10)
                        .rotationEffect(.degrees(45))
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                        .position(x: x(point.time), y: y(point.scale))
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                                .onChanged { value in
                                    if grab == nil {
                                        grab = value.location.x - x(point.time)
                                        model.selectPoint(point.id)
                                    }
                                    model.movePoint(point.id, to: time(value.location.x - (grab ?? 0)))
                                }
                                .onEnded { _ in grab = nil }
                        )
                }
            }
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
            .onTapGesture { model.selectPoint(nil) }
        }
        .frame(height: height)
    }
}

/// Settings of the selected zoom point, in the floating panel: level, travel speed, style, delete.
struct ZoomPanel: View {
    @ObservedObject var model: EditorModel

    private let speeds: [(seconds: Double, symbol: String, tip: String)] = [
        (0.25, "hare.fill", "0.25 s"), (0.6, "figure.walk", "0.6 s"), (1.2, "tortoise.fill", "1.2 s"),
    ]

    var body: some View {
        if let point = model.selectedPoint {
            ToolPanel {
                HStack(spacing: 8) {
                    Image(systemName: "plus.magnifyingglass").foregroundStyle(.secondary).font(.system(size: 13))
                    WedgeSlider(value: Binding(get: { point.scale }, set: { v in model.updateSelected { $0.scale = v } }), range: 1...6)
                    Text(String(format: "%.1f×", point.scale))
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        .frame(width: 34, alignment: .leading)
                }
                .tip(L("zoom.level"), trailing: true)

                IconSegments(
                    items: speeds.map { s in .init(value: s.seconds, tip: "\(L("zoom.speed")) \(s.tip)", icon: AnyView(Image(systemName: s.symbol).font(.system(size: 13)))) },
                    selection: speeds.first { abs($0.seconds - point.transition) < 0.06 }?.seconds,
                    onSelect: { v in model.updateSelected { $0.transition = v } }
                )

                IconSegments(
                    items: ZoomEase.allCases.map { e in .init(value: e, tip: L(e.labelKey), icon: AnyView(EaseGlyph(ease: e))) },
                    selection: point.ease,
                    onSelect: { v in model.updateSelected { $0.ease = v } }
                )

                Button { model.deleteSelected() } label: {
                    Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip(L("zoom.delete"), trailing: true)
            }
        }
    }
}

/// The region the camera shows at the selected point, drawn over the full frame.
/// Drag inside to move it, drag a corner to change the zoom level.
struct ZoomRegionOverlay: View {
    @ObservedObject var model: EditorModel
    let videoRect: CGRect

    private enum Part { case move, corner }
    @State private var part: Part?
    @State private var startPoint: ZoomPoint?
    @State private var startRect: CGRect = .zero

    private func viewRect(of point: ZoomPoint) -> CGRect {
        let n = model.region(of: point)
        return CGRect(
            x: videoRect.minX + n.minX * videoRect.width, y: videoRect.minY + n.minY * videoRect.height,
            width: n.width * videoRect.width, height: n.height * videoRect.height
        )
    }

    var body: some View {
        if let point = model.selectedPoint {
            let r = viewRect(of: point)
            ZStack(alignment: .topLeading) {
                Path { p in p.addRect(videoRect); p.addRect(r) }
                    .fill(Color.black.opacity(0.5), style: FillStyle(eoFill: true))
                Rectangle().stroke(Color.accentColor, lineWidth: 2)
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                ForEach(Array([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                               CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)].enumerated()), id: \.offset) { _, c in
                    Circle().fill(Color.white).overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
                        .frame(width: 12, height: 12).position(c)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if part == nil {
                            startPoint = point
                            startRect = r
                            let corners = [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
                                           CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
                            if corners.contains(where: { hypot($0.x - value.startLocation.x, $0.y - value.startLocation.y) < 18 }) {
                                part = .corner
                            } else if r.contains(value.startLocation) {
                                part = .move
                            }
                        }
                        guard let part, let start = startPoint else { return }
                        let base = model.baseRect
                        switch part {
                        case .move:
                            let dx = value.translation.width / (videoRect.width * base.width)
                            let dy = value.translation.height / (videoRect.height * base.height)
                            model.updateSelected { $0.center = CGPoint(x: start.center.x + dx, y: start.center.y + dy) }
                        case .corner:
                            let halfWidth = abs(value.location.x - startRect.midX)
                            let baseWidth = videoRect.width * base.width
                            model.updateSelected { $0.scale = baseWidth / max(halfWidth * 2, 1) }
                        }
                    }
                    .onEnded { _ in part = nil }
            )
        }
    }
}
