import SwiftUI

/// Lane under the timeline holding the zoom waypoints. Drag a diamond to retime it, click to edit it.
/// The tinted bar before each diamond is the travel time of the animation.
struct ZoomLane: View {
    @ObservedObject var model: EditorModel

    private let handleWidth: CGFloat = 14 // must match RangeSlider so both lanes line up
    private let height: CGFloat = 26
    private let space = "zoomlane"

    @State private var grab: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - handleWidth * 2, 1)
            let total = max(model.duration, 0.001)
            let x = { (t: Double) -> CGFloat in handleWidth + usable * CGFloat(t / total) }
            let time = { (x: CGFloat) -> Double in Double((x - handleWidth) / usable) * total }

            ZStack(alignment: .topLeading) {
                Capsule().fill(Color.primary.opacity(0.07))
                    .frame(width: usable, height: 12)
                    .offset(x: handleWidth, y: 7)
                    .allowsHitTesting(false)

                if model.zoomPoints.isEmpty {
                    Text(L("zoom.hint"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .offset(x: handleWidth + 10, y: 5)
                        .allowsHitTesting(false)
                }

                ForEach(Array(model.zoomPoints.enumerated()), id: \.element.id) { index, point in
                    let previous = index > 0 ? model.zoomPoints[index - 1].time : 0
                    let start = max(point.time - point.transition, previous)
                    Capsule().fill(Color.accentColor.opacity(0.45))
                        .frame(width: max(x(point.time) - x(start), 3), height: 8)
                        .offset(x: x(start), y: 9)
                        .allowsHitTesting(false)
                }

                ForEach(model.zoomPoints) { point in
                    let selected = point.id == model.selectedPointID
                    Rectangle()
                        .fill(selected ? Color.accentColor : Color.white)
                        .overlay(Rectangle().stroke(selected ? Color.white : Color.black.opacity(0.4), lineWidth: 1.2))
                        .frame(width: selected ? 12 : 10, height: selected ? 12 : 10)
                        .rotationEffect(.degrees(45))
                        .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                        .frame(width: 22, height: height)
                        .contentShape(Rectangle())
                        .position(x: x(point.time), y: height / 2)
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

/// Settings of the selected zoom point: level, travel speed and easing.
struct ZoomInspector: View {
    @ObservedObject var model: EditorModel

    var body: some View {
        if let point = model.selectedPoint {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text(L("zoom.level"))
                    Slider(value: Binding(get: { point.scale }, set: { v in model.updateSelected { $0.scale = v } }), in: 1...6)
                        .frame(width: 120)
                    Text(String(format: "%.1f×", point.scale)).monospacedDigit().frame(width: 38, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Text(L("zoom.speed"))
                    Slider(value: Binding(get: { point.transition }, set: { v in model.updateSelected { $0.transition = v } }), in: 0...2.5)
                        .frame(width: 110)
                    Text(String(format: "%.1f s", point.transition)).monospacedDigit().frame(width: 38, alignment: .leading)
                }
                Picker(L("zoom.ease"), selection: Binding(get: { point.ease }, set: { v in model.updateSelected { $0.ease = v } })) {
                    ForEach(ZoomEase.allCases, id: \.self) { Text(L($0.labelKey)).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                Spacer(minLength: 0)
                Button { model.deleteSelected() } label: { Image(systemName: "trash") }
                    .help(L("zoom.delete"))
                Button(L("zoom.done")) { model.selectPoint(nil) }
            }
            .controlSize(.small)
            .font(.system(size: 12))
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
                Text(String(format: "%.1f×", point.scale))
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .position(x: r.minX + 28, y: r.minY + 16)
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
