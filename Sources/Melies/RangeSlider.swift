import SwiftUI

/// Timeline with a trim range (two handles) and a scrubbable playhead.
///
/// All gestures read the pointer in one fixed coordinate space ("track"), never in the moving
/// handle's own space, and remember where the handle was grabbed so it follows the pointer 1:1.
struct RangeSlider: View {
    @ObservedObject var model: EditorModel

    private let handleWidth: CGFloat = 14
    private let height: CGFloat = 46
    private let space = "track"

    /// Distance between the pointer and the handle edge at the start of a drag.
    @State private var grab: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - handleWidth * 2, 1)
            let total = max(model.duration, 0.001)
            let x = { (t: Double) -> CGFloat in handleWidth + usable * CGFloat(t / total) }
            let time = { (x: CGFloat) -> Double in Double((x - handleWidth) / usable) * total }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.07))
                    .frame(height: height)

                // Kept range.
                Rectangle()
                    .fill(Color.accentColor.opacity(0.32))
                    .frame(width: max(x(model.end) - x(model.start), 0), height: height)
                    .offset(x: x(model.start))
                    .allowsHitTesting(false)

                // Playhead.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: height)
                    .offset(x: x(model.current) - 1)
                    .allowsHitTesting(false)

                // Start handle sits just left of the kept range.
                handle(systemImage: "chevron.compact.right", leading: true)
                    .offset(x: x(model.start) - handleWidth)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                            .onChanged { value in
                                if grab == nil { grab = value.location.x - x(model.start); model.player.pause() }
                                model.setStart(time(value.location.x - (grab ?? 0)))
                            }
                            .onEnded { _ in grab = nil }
                    )

                // End handle sits just right of the kept range.
                handle(systemImage: "chevron.compact.left", leading: false)
                    .offset(x: x(model.end))
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                            .onChanged { value in
                                if grab == nil { grab = value.location.x - x(model.end); model.player.pause() }
                                model.setEnd(time(value.location.x - (grab ?? 0)))
                            }
                            .onEnded { _ in grab = nil }
                    )
            }
            .coordinateSpace(name: space)
            .contentShape(Rectangle())
            // Click or drag anywhere else to scrub inside the kept range.
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(space))
                    .onChanged { value in
                        model.player.pause()
                        model.seek(to: min(max(time(value.location.x), model.start), model.end))
                    }
            )
        }
        .frame(height: height)
    }

    private func handle(systemImage: String, leading: Bool) -> some View {
        let corners: UnevenRoundedRectangle = leading
            ? UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 7, topTrailingRadius: 7, style: .continuous)
        return ZStack {
            corners.fill(Color.accentColor)
            Image(systemName: systemImage).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: handleWidth, height: height)
        .contentShape(Rectangle())
    }
}
