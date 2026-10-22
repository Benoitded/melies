import SwiftUI

/// Bars showing when each annotation is on screen. Drag a bar to move it, drag its ends to retime it.
struct AnnotationLane: View {
    @ObservedObject var model: EditorModel

    private let handleWidth: CGFloat = 14 // must match RangeSlider so the lanes line up
    private let rowHeight: CGFloat = 22
    private let space = "annotationlane"

    private enum Drag { case move(grab: Double, length: Double), start, end }
    @State private var drag: Drag?

    /// Greedy row assignment so overlapping bars do not hide each other.
    private var rows: [UUID: Int] {
        var result: [UUID: Int] = [:]
        var ends: [Double] = []
        for a in model.annotations.sorted(by: { $0.start < $1.start }) {
            if let row = ends.firstIndex(where: { $0 <= a.start }) {
                result[a.id] = row
                ends[row] = a.end
            } else {
                result[a.id] = ends.count
                ends.append(a.end)
            }
        }
        return result
    }

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
                                    .stroke(selected ? Color.white : Color.black.opacity(0.25), lineWidth: selected ? 2 : 1)
                            )
                            .overlay(alignment: .leading) {
                                Image(systemName: icon(a.kind))
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(a.color.luminance > 0.6 ? Color.black.opacity(0.7) : Color.white)
                                    .padding(.leading, 7)
                            }
                            .frame(width: width, height: rowHeight - 4)
                            .contentShape(Rectangle())
                            .offset(x: x(a.start), y: CGFloat(layout[a.id] ?? 0) * rowHeight + 2)
                            .highPriorityGesture(
                                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                                    .onChanged { value in
                                        if drag == nil {
                                            model.selectAnnotation(a.id)
                                            let edge: CGFloat = 8
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
                                    .onEnded { _ in drag = nil }
                            )
                    }
                }
                .coordinateSpace(name: space)
            }
            .frame(height: CGFloat(rowCount) * rowHeight + 4)
        }
    }

    private func icon(_ kind: AnnotationKind) -> String {
        switch kind {
        case .arrow: return "arrow.up.right"
        case .text: return "textformat"
        case .rect: return "rectangle"
        }
    }
}
