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

        var body: some View {
            VStack(spacing: 12) {
                TopBar(session: session, model: model).zIndex(1)
                GeometryReader { geo in
                    let area = CGRect(origin: .zero, size: geo.size)
                    let video = model.sourceSize.width > 0
                        ? AVMakeRect(aspectRatio: model.sourceSize, insideRect: area)
                        : area
                    ZStack {
                        Checkerboard()
                        PlayerView(player: model.player)
                            .frame(width: video.width, height: video.height)
                            .position(x: video.midX, y: video.midY)
                        if model.cropMode || model.cropRect != nil {
                            CropOverlay(model: model, videoRect: video)
                        }
                    }
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
