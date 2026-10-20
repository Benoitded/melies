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

    /// Invisible buttons that carry the Shottr-style keyboard shortcuts.
    private var shortcuts: some View {
        Group {
            Button("") {
                if let model = session.model, model.cropMode { model.cancelCrop() } else { close() }
            }.keyboardShortcut(.escape, modifiers: [])
            Button("") { session.chooseFile() }.keyboardShortcut("o", modifiers: [.command, .shift])
            if let model = session.model {
                Button("") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("") { model.toggleCrop() }.keyboardShortcut("c", modifiers: [])
                Button("") { if model.cropMode { model.confirmCrop() } }.keyboardShortcut(.return, modifiers: [])
                Button("") { model.setIn() }.keyboardShortcut("i", modifiers: [])
                Button("") { model.setOut() }.keyboardShortcut("o", modifiers: [])
                Button("") { model.step(frames: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { model.step(frames: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { model.step(frames: -10) }.keyboardShortcut(.leftArrow, modifiers: [.shift])
                Button("") { model.step(frames: 10) }.keyboardShortcut(.rightArrow, modifiers: [.shift])
            }
        }
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
                    Button(L("empty.latest")) { session.openLatest() }
                    Button(L("empty.open")) { session.chooseFile() }
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
                    ZStack {
                        Checkerboard()
                        PlayerView(player: model.player)
                            .frame(width: video.width, height: video.height)
                            .position(x: video.midX, y: video.midY)
                        if model.cropMode || model.cropRect != nil {
                            CropOverlay(model: model, videoRect: video)
                        }
                    }
                    .contentShape(Rectangle())
                    // Double click: 100% under the pointer, or back to fit.
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { value in
                        if !model.cropMode { model.toggleActual(at: value.location) }
                    })
                    // Grab and drag the video when it is zoomed in.
                    .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { value in
                        guard !model.cropMode, model.zoom > 1.0001 else { return }
                        model.panBy(CGSize(width: value.translation.width - lastDrag.width,
                                           height: value.translation.height - lastDrag.height))
                        lastDrag = value.translation
                    }.onEnded { _ in lastDrag = .zero })
                    .onAppear { updateCanvas(geo) }
                    .onChange(of: geo.size) { _, _ in updateCanvas(geo) }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 16)

                RangeSlider(model: model).padding(.horizontal, 16)

                HStack(spacing: 10) {
                    Button { model.togglePlay() } label: {
                        Image(systemName: model.isPlaying ? "pause.fill" : "play.fill").frame(width: 18)
                    }
                    Text(timeLabel).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                    Spacer()
                    if let status = model.status {
                        Text(status).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if model.busy { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 16)
        }

        private var timeLabel: String {
            String(format: "%.2f s   [%.2f → %.2f]  =  %.2f s", model.current, model.start, model.end, model.end - model.start)
        }
    }
}
