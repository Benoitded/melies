import SwiftUI

/// Bars showing when each annotation is on screen. Drag a bar to move it, drag its ends to retime it.
struct AnnotationLane: View {
    @ObservedObject var model: EditorModel

    private let handleWidth: CGFloat = 14 // must match RangeSlider so the lanes line up
    private let rowHeight: CGFloat = 22
    private let space = "annotationlane"

    private enum Drag { case move(grab: Double, length: Double), start, end }
    @State private var drag: Drag?
    @State private var hoveredID: UUID?
    /// Rows are frozen while a bar is being dragged, so bars never swap places under the pointer.
    @State private var frozenRows: [UUID: Int]?

    /// Greedy row assignment so overlapping bars do not hide each other. Bars are placed in creation order
    /// (not by start time), so retiming one bar does not make the rows trade places.
    private var computedRows: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var occupied: [[(start: Double, end: Double)]] = []
        for a in model.annotations {
            let free = occupied.firstIndex { row in row.allSatisfy { a.end <= $0.start || a.start >= $0.end } }
            let index = free ?? occupied.count
            if free == nil { occupied.append([]) }
            occupied[index].append((a.start, a.end))
            result[a.id] = index
        }
        return result
    }

    private var rows: [UUID: Int] { frozenRows ?? computedRows }

    var rowCount: Int { (rows.values.max() ?? -1) + 1 }

    var body: some View {
        if !model.annotations.isEmpty {
            let layout = rows
            GeometryReader { geo in
                let usable = max(geo.size.width - handleWidth * 2, 1)
                let total = max(model.duration, 0.001)
                let x = { (t: Double) -> CGFloat in handleWidth + usable * CGFloat(t / total) }
                let time = { (x: CGFloat) -> Double in Double((x - handleWidth) / usable) * total }

                ZStack(alignment: .topLeading) {
                    ForEach(model.annotations) { a in
                        let selected = a.id == model.selectedAnnotationID
                        let width = max(x(a.end) - x(a.start), 18)
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(a.color.color.opacity(selected ? 0.95 : 0.7))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(selected ? Color.accentColor : Color.black.opacity(0.25), lineWidth: selected ? 2.5 : 1)
                            )
                            .overlay(alignment: .leading) {
                                Image(systemName: icon(a.kind))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(a.color.luminance > 0.6 ? Color.black.opacity(0.7) : Color.white)
                                    .padding(.leading, 17)
                            }
                            .overlay(alignment: .leading) {
                                // Tracked: the followed span is lighter, with a target icon where it starts and,
                                // when the object was lost, a red cross where it stopped.
                                if a.isTracked, let last = a.track.last {
                                    let first = a.track.first?.t ?? a.trackStart // followed on both sides of where it was started
                                    let from = x(min(max(first, a.start), a.end)) - x(a.start)
                                    let followed = max(x(min(last.t, a.end)) - x(a.start) - from, 0)
                                    ZStack(alignment: .leading) {
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .fill(.white.opacity(0.30)).frame(width: followed)
                                        Image(systemName: "scope").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                                            .padding(.leading, 3)
                                        if a.trackLoss != nil {
                                            Image(systemName: "xmark.circle.fill").font(.system(size: 12))
                                                .foregroundStyle(.white, .red)
                                                .offset(x: max(followed - 8, 0))
                                        }
                                    }
                                    .frame(height: rowHeight - 4)
                                    .offset(x: from)
                                    .allowsHitTesting(false)
                                }
                            }
                            .overlay { grips(visible: selected || hoveredID == a.id) }
                            .frame(width: width, height: rowHeight - 4)
                            .contentShape(Rectangle())
                            .grabCursor(dragging: drag != nil)
                            .onHover { inside in hoveredID = inside ? a.id : (hoveredID == a.id ? nil : hoveredID) }
                            .offset(x: x(a.start), y: CGFloat(layout[a.id] ?? 0) * rowHeight + 2)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                                    .onChanged { value in
                                        if drag == nil {
                                            frozenRows = computedRows
                                            model.selectAnnotation(a.id)
                                            let edge: CGFloat = 12
                                            if value.startLocation.x - x(a.start) < edge { drag = .start }
                                            else if x(a.end) - value.startLocation.x < edge { drag = .end }
                                            else { drag = .move(grab: time(value.startLocation.x) - a.start, length: a.end - a.start) }
                                        }
                                        let t = time(value.location.x)
                                        switch drag {
                                        case .start: model.updateAnnotation(a.id) { $0.start = min(t, $0.end - 0.2) }
                                        case .end: model.updateAnnotation(a.id) { $0.end = max(t, $0.start + 0.2) }
                                        case .move(let grab, let length):
                                            let start = min(max(t - grab, 0), max(model.duration - length, 0))
                                            model.updateAnnotation(a.id) { $0.start = start; $0.end = start + length }
                                        case nil: break
                                        }
                                    }
                                    .onEnded { _ in drag = nil; frozenRows = nil }
                            )
                    }
                }
                .coordinateSpace(name: space)
            }
            .frame(height: CGFloat((layout.values.max() ?? -1) + 1) * rowHeight + 4) // from the layout computed above, not recomputed
        }
    }

    /// Two small grips at the ends of a bar: they appear on hover and on the selected bar, and show the
    /// resize cursor, so it is clear the ends can be dragged to change when the annotation starts and stops.
    private func grips(visible: Bool) -> some View {
        HStack {
            grip(visible)
            Spacer(minLength: 0)
            grip(visible)
        }
    }

    private func grip(_ visible: Bool) -> some View {
        ZStack {
            Color.clear
            Capsule()
                .fill(Color.white)
                .overlay(Capsule().stroke(Color.black.opacity(0.35), lineWidth: 0.8))
                .frame(width: 4, height: 11)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
                .opacity(visible ? 1 : 0)
        }
        .frame(width: 12)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
    }

    private func icon(_ kind: AnnotationKind) -> String {
        switch kind {
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .rect: return "rectangle"
        case .spotlight: return "circle.lefthalf.filled.inverse"
        case .blur: return "squareshape.split.3x3"
        }
    }
}
