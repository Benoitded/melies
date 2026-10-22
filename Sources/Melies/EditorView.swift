import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var session: EditorSession
    let close: () -> Void

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            if let model = session.model {
                Loaded(session: session, model: model)
            } else {
                Empty(session: session)
            }
            shortcuts
        }
        .ignoresSafeArea(.container, edges: .top)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { session.open(url) } }
            }
            return true
        }
    }

    /// Keys are handled by `EditorWindowController` (see its key monitor); only Cmd+Shift+O stays here.
    private var shortcuts: some View {
        Button("") { session.chooseFile() }
            .keyboardShortcut("o", modifiers: [.command, .shift])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    private struct Empty: View {
        @ObservedObject var session: EditorSession

        var body: some View {
            VStack(spacing: 14) {
                Image(systemName: "film.stack").font(.system(size: 44)).foregroundStyle(.secondary)
                Text(L("empty.title")).font(.title3.weight(.semibold))
                Text(L("empty.hint"))
                    .foregroundStyle(.secondary)
                HStack {
                    Button(L("empty.latest")) { session.openLatest() }.buttonStyle(.glass)
                    Button(L("empty.open")) { session.chooseFile() }.buttonStyle(.glass)
                }
            }
        }
    }

    private struct Loaded: View {
        @ObservedObject var session: EditorSession
        @ObservedObject var model: EditorModel
        @State private var lastDrag: CGSize = .zero

        private func updateCanvas(_ geo: GeometryProxy) {
            model.canvasSize = geo.size
            model.canvasOrigin = geo.frame(in: .global).origin
        }

        var body: some View {
            VStack(spacing: 12) {
                TopBar(session: session, model: model).zIndex(1)
                GeometryReader { geo in
                    let video = model.videoRect(in: geo.size)
                    // With zoom points and nothing selected, preview what the camera sees.
                    let region = model.previewingCamera ? model.cameraRegion(at: model.current) : CGRect(x: 0, y: 0, width: 1, height: 1)
                    let playerW = video.width / max(region.width, 0.0001)
                    let playerH = video.height / max(region.height, 0.0001)
                    ZStack {
                        Checkerboard()
                        ZStack(alignment: .topLeading) {
                            PlayerView(player: model.player)
                                .frame(width: playerW, height: playerH)
                                .offset(x: -region.minX * playerW, y: -region.minY * playerH)
                        }
                        .frame(width: video.width, height: video.height, alignment: .topLeading)
                        .clipped()
                        .position(x: video.midX, y: video.midY)
                        if !model.annotations.isEmpty || model.tool != .select || (model.showClicks && model.hasClicks), !model.cropMode, model.selectedPoint == nil {
                            AnnotationOverlay(model: model, video: video, region: region)
                        }
                        if model.cropMode || (model.cropRect != nil && !model.previewingCamera) {
                            CropOverlay(model: model, videoRect: video)
                        }
                        if model.selectedPoint != nil {
                            ZoomRegionOverlay(model: model, videoRect: video)
                        }
                    }
                    .contentShape(Rectangle())
                    // Double click: 100% under the pointer, or back to fit.
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                        if !model.cropMode { model.toggleActual(at: value.location) }
                    })
                    // Grab and drag the video when it is zoomed in.
                    .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { value in
                        guard !model.cropMode, !model.annotationGestureActive, model.zoom > 1.0001 else { return }
                        model.panBy(CGSize(width: value.translation.width - lastDrag.width,
                                           height: value.translation.height - lastDrag.height))
                        lastDrag = value.translation
                    }.onEnded { _ in lastDrag = .zero })
                    .onAppear { updateCanvas(geo) }
                    .onChange(of: geo.size) { _, _ in updateCanvas(geo) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    ZoomPanel(model: model).padding(10)
                    AnnotationPanel(model: model).padding(10)
                }
                .padding(.horizontal, 16)

                RangeSlider(model: model).padding(.horizontal, 16)
                ZoomLane(model: model).padding(.horizontal, 16)
                AnnotationLane(model: model).padding(.horizontal, 16)

                HStack(spacing: 12) {
                    Button { model.togglePlay() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    HStack(spacing: 5) {
                        Text(timecode(max(model.current - model.start, 0)))
                        Text("/").foregroundStyle(.tertiary)
                        Text(timecode(model.end - model.start)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12).monospacedDigit())
                    Spacer()
                    if model.hasAudio {
                        Button { model.includeAudio.toggle() } label: {
                            Image(systemName: model.includeAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 12))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .tip(model.includeAudio ? L("tip.audio.on") : L("tip.audio.off"), trailing: true)
                    }
                    if let status = model.status {
                        Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if model.busy { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 14)
        }

        private func timecode(_ seconds: Double) -> String {
            let s = max(seconds, 0)
            return String(format: "%d:%02d.%d", Int(s) / 60, Int(s) % 60, Int((s * 10).truncatingRemainder(dividingBy: 10)))
        }
    }
}
