import SwiftUI

/// Draws the annotations over the video and handles creating, selecting, moving and reshaping them.
/// `video` is the on-screen rectangle of the picture; `region` is the part of the source it shows.
struct AnnotationOverlay: View {
    @ObservedObject var model: EditorModel
    let video: CGRect
    let region: CGRect   // normalized source coordinates

    private enum Part: Equatable { case body, tail, head, corner(Int) }
    private enum Mode {
        case create(UUID, AnnotationKind)
        case edit(UUID, Part, Annotation)
        case textClick
    }
    @State private var mode: Mode?

    private var source: CGSize { model.sourceSize }
    private var scale: CGFloat { video.width / max(region.width * source.width, 1) }

    private func toView(_ n: CGPoint) -> CGPoint {
        CGPoint(x: video.minX + (n.x - region.minX) / region.width * video.width,
                y: video.minY + (n.y - region.minY) / region.height * video.height)
    }

    private func toNorm(_ v: CGPoint) -> CGPoint {
        CGPoint(x: region.minX + (v.x - video.minX) / video.width * region.width,
                y: region.minY + (v.y - video.minY) / video.height * region.height)
    }

    private func viewRect(fromSource r: CGRect) -> CGRect {
        let a = toView(CGPoint(x: r.minX / source.width, y: r.minY / source.height))
        let b = toView(CGPoint(x: r.maxX / source.width, y: r.maxY / source.height))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    private var visible: [Annotation] {
        model.annotations.filter { AnnotationRenderer.isVisible($0, at: model.current) }
    }

    // MARK: View

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                context.withCGContext { cg in
                    cg.saveGState()
                    cg.clip(to: video)
                    cg.translateBy(x: video.minX, y: video.minY)
                    cg.scaleBy(x: scale, y: scale)
                    cg.translateBy(x: -region.minX * source.width, y: -region.minY * source.height)
                    if let frame = model.currentFrameImage {
                        AnnotationRenderer.drawBlurs(frame: frame, list: model.annotations, at: model.current, in: cg,
                                                     source: source, animated: model.isPlaying, ciContext: EditorModel.previewContext)
                    }
                    AnnotationRenderer.draw(model.annotations, at: model.current, in: cg, source: source, animated: model.isPlaying)
                    cg.restoreGState()
                }
            }
            .allowsHitTesting(false)

            if let a = model.selectedAnnotation, AnnotationRenderer.isVisible(a, at: model.current) {
                selection(for: a).allowsHitTesting(false)
            }

            Color.clear
                .contentShape(Rectangle())
                .gesture(drag)
                .pointerStyle(model.tool == .select ? nil : .rectSelection)
        }
    }

    @ViewBuilder
    private func selection(for a: Annotation) -> some View {
        switch a.kind {
        case .arrow:
            handleDot(toView(a.p1))
            handleDot(toView(a.p2))
        case .rect, .spotlight, .blur:
            ForEach(Array(cornerPoints(a).enumerated()), id: \.offset) { _, p in handleDot(p) }
            if a.kind != .rect {
                let r = viewRect(fromSource: AnnotationRenderer.normalizedRect(a, source))
                Rectangle().stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.2, dash: [5, 3]))
                    .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
            }
        case .text:
            let r = viewRect(fromSource: AnnotationRenderer.bounds(of: a, source: source)).insetBy(dx: -3, dy: -3)
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                .frame(width: r.width, height: r.height)
                .offset(x: r.minX, y: r.minY)
        }
    }

    private func handleDot(_ p: CGPoint) -> some View {
        Circle().fill(Color.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
            .frame(width: 11, height: 11)
            .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
            .position(p)
    }

    /// Rectangle corners in view coordinates: top-left, top-right, bottom-left, bottom-right.
    private func cornerPoints(_ a: Annotation) -> [CGPoint] {
        let r = AnnotationRenderer.normalizedRect(a, source)
        let n = { (x: CGFloat, y: CGFloat) in toView(CGPoint(x: x / source.width, y: y / source.height)) }
        return [n(r.minX, r.minY), n(r.maxX, r.minY), n(r.minX, r.maxY), n(r.maxX, r.maxY)]
    }

    // MARK: Gesture

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if mode == nil { begin(value) }
                update(value)
            }
            .onEnded { value in
                finish(value)
                mode = nil
                model.annotationGestureActive = false
            }
    }

    private func begin(_ value: DragGesture.Value) {
        let start = value.startLocation
        switch model.tool {
        case .arrow, .rect, .spotlight, .blur:
            let kind: AnnotationKind = model.tool == .arrow ? .arrow : (model.tool == .rect ? .rect : (model.tool == .spotlight ? .spotlight : .blur))
            let id = model.addAnnotation(kind, at: toNorm(start))
            model.annotationGestureActive = true
            mode = .create(id, kind)
        case .text:
            model.annotationGestureActive = true
            mode = .textClick
        case .select:
            if let (id, part) = hit(at: start), let a = model.annotations.first(where: { $0.id == id }) {
                model.selectAnnotation(id)
                model.annotationGestureActive = true
                mode = .edit(id, part, a)
            } else {
                model.selectAnnotation(nil)
            }
        }
    }

    private func update(_ value: DragGesture.Value) {
        guard let mode else { return }
        let here = toNorm(value.location)
        switch mode {
        case .create(let id, _):
            model.updateAnnotation(id) { $0.p2 = here }
        case .edit(let id, let part, let original):
            let dx = value.translation.width / video.width * region.width
            let dy = value.translation.height / video.height * region.height
            model.updateAnnotation(id) { a in
                switch part {
                case .body:
                    a.p1 = CGPoint(x: original.p1.x + dx, y: original.p1.y + dy)
                    a.p2 = CGPoint(x: original.p2.x + dx, y: original.p2.y + dy)
                case .tail: a.p1 = here
                case .head: a.p2 = here
                case .corner(let i):
                    var lo = CGPoint(x: min(original.p1.x, original.p2.x), y: min(original.p1.y, original.p2.y))
                    var hi = CGPoint(x: max(original.p1.x, original.p2.x), y: max(original.p1.y, original.p2.y))
                    if i == 0 || i == 2 { lo.x = here.x } else { hi.x = here.x }
                    if i == 0 || i == 1 { lo.y = here.y } else { hi.y = here.y }
                    a.p1 = lo
                    a.p2 = hi
                }
            }
        case .textClick:
            break
        }
    }

    private func finish(_ value: DragGesture.Value) {
        guard let mode else { return }
        switch mode {
        case .create(let id, _):
            let moved = hypot(value.translation.width, value.translation.height)
            if moved < 6 {
                model.annotations.removeAll { $0.id == id } // a click without a drag draws nothing
            } else {
                model.selectAnnotation(id)
            }
            model.setTool(.select)
            if moved >= 6 { model.selectAnnotation(id) }
        case .textClick:
            let id = model.addAnnotation(.text, at: toNorm(value.startLocation))
            model.setTool(.select)
            model.selectAnnotation(id)
            model.requestTextFocus()
        case .edit:
            break
        }
    }

    // MARK: Hit testing

    /// Finds what is under `point` (view coordinates): a handle of the selection first, then the top-most annotation.
    private func hit(at point: CGPoint) -> (UUID, Part)? {
        let reach: CGFloat = 12
        if let a = model.selectedAnnotation, AnnotationRenderer.isVisible(a, at: model.current) {
            switch a.kind {
            case .arrow:
                if hypot(point.x - toView(a.p1).x, point.y - toView(a.p1).y) < reach { return (a.id, .tail) }
                if hypot(point.x - toView(a.p2).x, point.y - toView(a.p2).y) < reach { return (a.id, .head) }
            case .rect, .spotlight, .blur:
                for (i, c) in cornerPoints(a).enumerated() where hypot(point.x - c.x, point.y - c.y) < reach { return (a.id, .corner(i)) }
            case .text:
                break
            }
        }
        let n = toNorm(point)
        let px = CGPoint(x: n.x * source.width, y: n.y * source.height)
        let slop = 10 / max(scale, 0.0001)
        for a in visible.reversed() where AnnotationRenderer.hit(a, at: px, source: source, slop: slop) {
            return (a.id, .body)
        }
        return nil
    }
}
