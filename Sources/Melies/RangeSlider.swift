import SwiftUI

/// Timeline with a trim range (two handles) and a draggable playhead.
struct RangeSlider: View {
    @ObservedObject var model: EditorModel

    private let handleWidth: CGFloat = 12
    private let height: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let usable = width - handleWidth * 2
            let total = max(model.duration, 0.001)
            let startX = handleWidth + usable * model.start / total
            let endX = handleWidth + usable * model.end / total
            let playX = handleWidth + usable * model.current / total

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.07))

                // Selected range.
                Rectangle()
                    .fill(Color.accentColor.opacity(0.35))
                    .frame(width: max(endX - startX, 0), height: height)
                    .offset(x: startX)

                // Playhead.
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: height)
                    .offset(x: playX - 1)

                handle(systemImage: "chevron.compact.right")
                    .offset(x: startX - handleWidth)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let t = (value.location.x + startX - handleWidth - handleWidth) / usable * total
                        model.setStart(t)
                    })

                handle(systemImage: "chevron.compact.left")
                    .offset(x: endX)
                    .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                        let t = (value.location.x + endX - handleWidth) / usable * total
                        model.setEnd(t)
                    })
            }
            .frame(height: height)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                let t = (value.location.x - handleWidth) / usable * total
                model.seek(to: min(max(t, model.start), model.end))
            })
        }
        .frame(height: height)
    }

    private func handle(systemImage: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.accentColor)
            Image(systemName: systemImage).font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: handleWidth, height: height)
    }
}
