import SwiftUI

/// Crop rectangle over the video. Drag inside to move, drag an edge or corner to resize.
/// `videoRect` is where the video is actually drawn inside this view.
struct CropOverlay: View {
    @ObservedObject var model: EditorModel
    let videoRect: CGRect

    private enum Part { case move, left, right, top, bottom, topLeft, topRight, bottomLeft, bottomRight }
    @State private var part: Part?
    @State private var startRect: CGRect = .zero
    @State private var hover: Part?

    private let minSize: CGFloat = 40
    private let grab: CGFloat = 16

    private var rect: CGRect {
        let n = model.cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        return CGRect(
            x: videoRect.minX + n.minX * videoRect.width, y: videoRect.minY + n.minY * videoRect.height,
            width: n.width * videoRect.width, height: n.height * videoRect.height
        )
    }

    var body: some View {
        let r = rect
        ZStack(alignment: .topLeading) {
            Path { p in p.addRect(videoRect); p.addRect(r) }
                .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))

            Rectangle().stroke(Color.white, lineWidth: 1.5)
                .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)

            if model.cropMode {
                // Rule-of-thirds guides.
                Path { p in
                    for i in 1...2 {
                        let x = r.minX + r.width * CGFloat(i) / 3
                        let y = r.minY + r.height * CGFloat(i) / 3
                        p.move(to: CGPoint(x: x, y: r.minY)); p.addLine(to: CGPoint(x: x, y: r.maxY))
                        p.move(to: CGPoint(x: r.minX, y: y)); p.addLine(to: CGPoint(x: r.maxX, y: y))
                    }
                }
                .stroke(Color.white.opacity(0.35), lineWidth: 0.5)

                ForEach(Array(handlePoints(r).enumerated()), id: \.offset) { _, point in
                    RoundedRectangle(cornerRadius: 2.5)
                        .fill(Color.white)
                        .overlay(RoundedRectangle(cornerRadius: 2.5).stroke(Color.black.opacity(0.45), lineWidth: 0.5))
                        .frame(width: 10, height: 10)
                        .position(point)
                }
            }
        }
        .contentShape(Rectangle())
        .allowsHitTesting(model.cropMode)
        .onContinuousHover { phase in
            switch phase {
            case .active(let point): hover = model.cropMode ? hit(point, in: rect) : nil
            case .ended: hover = nil
            }
        }
        .pointerStyle(model.cropMode ? cursor(for: part ?? hover, dragging: part != nil) : nil)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if part == nil {
                        startRect = rect
                        part = hit(value.startLocation, in: startRect)
                    }
                    if let part { apply(part, translation: value.translation) }
                }
                .onEnded { _ in part = nil }
        )
    }

    /// Handle centers, nudged inside the video so they stay fully visible when the crop touches an edge.
    private func handlePoints(_ r: CGRect) -> [CGPoint] {
        let inner = videoRect.insetBy(dx: 6, dy: 6)
        return [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
            CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY),
        ].map { CGPoint(x: min(max($0.x, inner.minX), inner.maxX), y: min(max($0.y, inner.minY), inner.maxY)) }
    }

    private func cursor(for part: Part?, dragging: Bool) -> PointerStyle? {
        switch part {
        case .move?: return dragging ? .grabActive : .grabIdle
        case .left?: return .frameResize(position: .leading)
        case .right?: return .frameResize(position: .trailing)
        case .top?: return .frameResize(position: .top)
        case .bottom?: return .frameResize(position: .bottom)
        case .topLeft?: return .corner(0)
        case .topRight?: return .corner(1)
        case .bottomLeft?: return .corner(2)
        case .bottomRight?: return .corner(3)
        case nil: return nil
        }
    }

    private func hit(_ p: CGPoint, in r: CGRect) -> Part? {
        let nearL = abs(p.x - r.minX) < grab, nearR = abs(p.x - r.maxX) < grab
        let nearT = abs(p.y - r.minY) < grab, nearB = abs(p.y - r.maxY) < grab
        let withinX = p.x > r.minX - grab && p.x < r.maxX + grab
        let withinY = p.y > r.minY - grab && p.y < r.maxY + grab
        if nearL && nearT { return .topLeft }
        if nearR && nearT { return .topRight }
        if nearL && nearB { return .bottomLeft }
        if nearR && nearB { return .bottomRight }
        if nearL && withinY { return .left }
        if nearR && withinY { return .right }
        if nearT && withinX { return .top }
        if nearB && withinX { return .bottom }
        return r.contains(p) ? .move : nil
    }

    private func apply(_ part: Part, translation t: CGSize) {
        var minX = startRect.minX, maxX = startRect.maxX
        var minY = startRect.minY, maxY = startRect.maxY

        if part == .move {
            let dx = min(max(t.width, videoRect.minX - minX), videoRect.maxX - maxX)
            let dy = min(max(t.height, videoRect.minY - minY), videoRect.maxY - maxY)
            minX += dx; maxX += dx; minY += dy; maxY += dy
        } else {
            if [.left, .topLeft, .bottomLeft].contains(part) { minX = min(max(minX + t.width, videoRect.minX), maxX - minSize) }
            if [.right, .topRight, .bottomRight].contains(part) { maxX = max(min(maxX + t.width, videoRect.maxX), minX + minSize) }
            if [.top, .topLeft, .topRight].contains(part) { minY = min(max(minY + t.height, videoRect.minY), maxY - minSize) }
            if [.bottom, .bottomLeft, .bottomRight].contains(part) { maxY = max(min(maxY + t.height, videoRect.maxY), minY + minSize) }
        }

        model.cropRect = CGRect(
            x: (minX - videoRect.minX) / videoRect.width, y: (minY - videoRect.minY) / videoRect.height,
            width: (maxX - minX) / videoRect.width, height: (maxY - minY) / videoRect.height
        )
    }
}
