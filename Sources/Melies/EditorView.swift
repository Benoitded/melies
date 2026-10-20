import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var session: EditorSession
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            if let model = session.model {
                Loaded(session: session, model: model)
            } else {
                Empty(session: session)
            }
            shortcuts
        }
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
            Button("") { close() }.keyboardShortcut(.escape, modifiers: [])
            Button("") { session.chooseFile() }.keyboardShortcut("o", modifiers: [.command, .shift])
            Button("") { session.loadFromPasteboard() }.keyboardShortcut("v", modifiers: [.command, .shift])
            if let model = session.model {
                Button("") { model.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button("") { model.setIn() }.keyboardShortcut("i", modifiers: [])
                Button("") { model.setOut() }.keyboardShortcut("o", modifiers: [])
                Button("") { model.step(frames: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button("") { model.step(frames: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { model.step(frames: -10) }.keyboardShortcut(.leftArrow, modifiers: [.shift])
                Button("") { model.step(frames: 10) }.keyboardShortcut(.rightArrow, modifiers: [.shift])
                Button("") { Task { await model.copy() } }.keyboardShortcut("c", modifiers: [.command])
                Button("") { Task { await model.save() } }.keyboardShortcut("s", modifiers: [.command])
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
                PlayerView(player: model.player)
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
