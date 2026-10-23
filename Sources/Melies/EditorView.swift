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

    /// Shown instead of the editor when the file is not a video Melies can read.
    private struct UnreadableVideo: View {
        let message: String
        @ObservedObject var session: EditorSession

        var body: some View {
            VStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 40)).foregroundStyle(.orange)
                Text(message).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                Text(L("error.unreadable.hint")).foregroundStyle(.secondary).multilineTextAlignment(.center)
                HStack {
                    Button(L("empty.open")) { session.chooseFile() }.buttonStyle(.glass).clickCursor()
                    Button(L("error.close")) { EditorWindowController.shared.close() }.buttonStyle(.glass).clickCursor()
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
                    Button(L("empty.latest")) { session.openLatest() }.buttonStyle(.glass).clickCursor()
                    Button(L("empty.open")) { session.chooseFile() }.buttonStyle(.glass).clickCursor()
                }
            }
        }
    }

    private struct Loaded: View {
        @ObservedObject var session: EditorSession
        var model: EditorModel
        @State private var lastDrag: CGSize = .zero

        private func updateCanvas(_ geo: GeometryProxy) {
            model.canvasSize = geo.size
            model.canvasOrigin = geo.frame(in: .global).origin
        }

        var body: some View {
            VStack(spacing: 12) {
                if let problem = model.loadError {
                    UnreadableVideo(message: problem, session: session)
                } else {
                TopBar(session: session, model: model).zIndex(1)
                GeometryReader { geo in
                    let video = model.videoRect(in: geo.size)
                    // With zoom points and nothing selected, preview what the camera sees.
                    let region = model.previewingCamera ? model.cameraRegion(at: model.current) : CGRect(x: 0, y: 0, width: 1, height: 1)
                    let playerW = video.width / max(region.width, 0.0001)
                    let playerH = video.height / max(region.height, 0.0001)
                    ZStack {
                        Checkerboard()
                        if model.frame.enabled { FramePanel(style: model.frame, video: video) }
                        ZStack(alignment: .topLeading) {
                            PlayerView(player: model.player)
                                .frame(width: playerW, height: playerH)
                                .offset(x: -region.minX * playerW, y: -region.minY * playerH)
                        }
                        .frame(width: video.width, height: video.height, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: model.frame.enabled ? CGFloat(model.frame.radius) * video.width : 0, style: .circular))
                        .position(x: video.midX, y: video.midY)
                        if !model.annotations.isEmpty || model.tool != .select || (model.showClicks && model.hasClicks), !model.cropMode, model.selectedPoint == nil {
                            AnnotationOverlay(model: model, video: video, region: region)
                        }
                        if model.captions.showInExport, !model.captions.lines.isEmpty {
                            CaptionOverlay(model: model, video: video)
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
                .overlay(alignment: .top) { AIBadge() }
                .animation(.easeInOut(duration: 0.2), value: MCPServer.shared.showBadge)
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
                    .clickCursor()
                    .buttonBorderShape(.circle)
                    HStack(spacing: 5) {
                        ElapsedLabel(model: model)
                        Text("/").foregroundStyle(.tertiary)
                        Text(timecode(model.end - model.start)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 12).monospacedDigit())
                    if let status = model.status {
                        Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
                    }
                    if model.busy {
                        if model.exportProgress > 0 {
                            ProgressView(value: model.exportProgress).progressViewStyle(.linear).frame(width: 70)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                        Button { model.cancelExport() } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .clickCursor()
                        .tip(L("tip.cancel_export"), trailing: true)
                    }
                    Spacer()
                    if model.hasAudio {
                        Button { model.includeAudio.toggle() } label: {
                            Image(systemName: model.includeAudio ? "speaker.wave.2.fill" : "speaker.slash.fill")
                                .font(.system(size: 12))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.glass)
                        .clickCursor()
                        .buttonBorderShape(.circle)
                        .tip(model.includeAudio ? L("tip.audio.on") : L("tip.audio.off"), trailing: true)
                    }
                    CaptionsButton(model: model)
                    FrameOptionsButton(model: model)
                    ExportOptionsButton(model: model)
                }
                .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 14)
        }

        private func timecode(_ seconds: Double) -> String { Timecode.format(seconds) }
    }
}

enum Timecode {
    static func format(_ seconds: Double) -> String {
        let s = max(seconds, 0)
        return String(format: "%d:%02d.%d", Int(s) / 60, Int(s) % 60, Int((s * 10).truncatingRemainder(dividingBy: 10)))
    }
}

/// Elapsed time in the kept range: the one label that follows the playhead, so it is its own view.
private struct ElapsedLabel: View {
    var model: EditorModel
    var body: some View { Text(Timecode.format(max(model.current - model.start, 0))) }
}

private struct ExportOptionsButton: View {
    var model: EditorModel
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 12))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .clickCursor()
        .buttonBorderShape(.circle)
        .tip(L("exp.title"), trailing: true)
        .popover(isPresented: $open, arrowEdge: .top) { ExportOptionsView(model: model) }
    }
}

private struct FrameOptionsButton: View {
    var model: EditorModel
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: model.frame.enabled ? "rectangle.inset.filled" : "rectangle.dashed")
                .font(.system(size: 12))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .clickCursor()
        .buttonBorderShape(.circle)
        .tip(L("frame.title"), trailing: true)
        .popover(isPresented: $open, arrowEdge: .top) { FrameOptionsView(model: model) }
    }
}
