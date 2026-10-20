import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @ObservedObject var session: EditorSession
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            if let model = session.model {
                Loaded(model: model)
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
                Text("Aucune vidéo").font(.title3.weight(.semibold))
                Text("Glisse un fichier ici, ou ouvre-en un avec ⌘⇧O.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Dernière capture") { session.openLatest() }
                    Button("Ouvrir…") { session.chooseFile() }
                }
            }
        }
    }

    private struct Loaded: View {
        @ObservedObject var model: EditorModel

        var body: some View {
            VStack(spacing: 12) {
                PlayerView(player: model.player)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.top, 28)

                RangeSlider(model: model)

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
                    Button("Copier  ⌘C") { Task { await model.copy() } }.disabled(model.busy)
                    Button("Enregistrer  ⌘S") { Task { await model.save() } }
                        .buttonStyle(.borderedProminent).disabled(model.busy)
                }
            }
            .padding([.horizontal, .bottom], 16)
        }

        private var timeLabel: String {
            String(format: "%.2f s   [%.2f → %.2f]  =  %.2f s", model.current, model.start, model.end, model.end - model.start)
        }
    }
}
