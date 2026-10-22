import SwiftUI

/// Trim timeline: a strip of video frames (like Photos), two handles for the kept range,
/// and a scrubbable playhead.
///
/// All gestures read the pointer in one fixed coordinate space ("track"), never in the moving
/// handle's own space, and remember where the handle was grabbed so it follows the pointer 1:1.
struct RangeSlider: View {
    @ObservedObject var model: EditorModel

    private let handleWidth: CGFloat = 14
    private let height: CGFloat = 52
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
                // Frame strip.
                ZStack {
                    Rectangle().fill(Color.primary.opacity(0.08))
                    HStack(spacing: 0) {
                        ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, image in
                            Image(nsImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: usable / CGFloat(max(model.thumbnails.count, 1)), height: height)
                                .clipped()
                        }
                    }
                }
                .frame(width: usable, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
                .offset(x: handleWidth)
                .allowsHitTesting(false)

                // Frames outside the kept range are dimmed.
                Rectangle().fill(Color.black.opacity(0.55))
                    .frame(width: max(x(model.start) - handleWidth, 0), height: height)
                    .offset(x: handleWidth)
                    .allowsHitTesting(false)
                Rectangle().fill(Color.black.opacity(0.55))
                    .frame(width: max(handleWidth + usable - x(model.end), 0), height: height)
                    .offset(x: x(model.end))
                    .allowsHitTesting(false)

                // Frame around the kept range.
                Rectangle().stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: max(x(model.end) - x(model.start), 0), height: height)
                    .offset(x: x(model.start))
                    .allowsHitTesting(false)

                // Playhead.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2.5, height: height + 6)
                    .shadow(color: .black.opacity(0.5), radius: 1.5)
                    .offset(x: x(model.current) - 1.25, y: -3)
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
        let shape = leading
            ? UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7, bottomTrailingRadius: 0, topTrailingRadius: 0, style: .continuous)
            : UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 7, topTrailingRadius: 7, style: .continuous)
        return ZStack {
            shape.fill(Color.accentColor)
            Image(systemName: systemImage).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: handleWidth, height: height)
        .contentShape(Rectangle())
        .pointerStyle(.columnResize)
    }
}
