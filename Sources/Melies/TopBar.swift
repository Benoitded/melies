import SwiftUI

/// Shottr-style toolbar: actions, tools, then source info on the right.
struct TopBar: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var model: EditorModel
    @ObservedObject private var recorder = ScreenRecorder.shared

    var body: some View {
        HStack(spacing: 4) {
            BarButton(symbol: "doc.on.doc", title: "Copier le MP4 Twitter", shortcut: "(⌘C)", disabled: model.busy) {
                Task { await model.copy() }
            }
            BarButton(symbol: "square.and.arrow.down", title: "Enregistrer le MP4 Twitter", shortcut: "(⌘S)", disabled: model.busy) {
                Task { await model.save() }
            }
            divider
            BarButton(symbol: session.pinned ? "pin.fill" : "pin", title: "Garder au premier plan", active: session.pinned) {
                session.pinned.toggle()
            }
            BarButton(symbol: "square.and.arrow.up", title: "Partager", disabled: model.busy) {
                Task { await model.share(from: NSApp.keyWindow?.contentView) }
            }
            BarButton(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                      title: recorder.isRecording ? "Arrêter l'enregistrement" : "Enregistrer l'écran",
                      shortcut: "(⇧⌘6)", active: recorder.isRecording) {
                ScreenRecorder.shared.toggle()
            }
            divider
            BarButton(symbol: "scissors", title: "Trim", shortcut: "(I / O)", active: true) {}
            BarButton(symbol: "arrow.up.right", title: "Flèche", shortcut: "(A, v2)", disabled: true) {}
            BarButton(symbol: "textformat", title: "Texte", shortcut: "(T, v2)", disabled: true) {}
            BarButton(symbol: "ruler", title: "Mesure", shortcut: "(v2)", disabled: true) {}
            BarButton(symbol: "rectangle", title: "Rectangle", shortcut: "(R, v2)", disabled: true) {}
            BarButton(symbol: "viewfinder", title: "Spotlight et zoom", shortcut: "(Z, v2)", disabled: true) {}
            BarButton(symbol: "pencil", title: "Crayon", shortcut: "(v2)", disabled: true) {}
            BarButton(symbol: "ellipsis", title: "Plus", shortcut: "(v2)", disabled: true) {}

            Spacer(minLength: 12)

            info(value: sizeText, label: "Taille source")
            divider
            info(value: String(format: "%.1f s", max(model.end - model.start, 0)), label: "Durée")
            divider
            info(value: fpsText, label: "Export 30 fps")
        }
        .padding(.leading, 78) // room for the traffic lights
        .padding(.trailing, 16)
        .frame(height: 52)
    }

    private var sizeText: String {
        guard model.sourceSize.width > 0 else { return "..." }
        return "\(Int(model.sourceSize.width))×\(Int(model.sourceSize.height))"
    }

    private var fpsText: String {
        model.fps > 0 ? "\(Int(model.fps.rounded())) → 30 fps" : "..."
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1, height: 22).padding(.horizontal, 6)
    }

    private func info(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .fixedSize()
    }
}

struct BarButton: View {
    let symbol: String
    let title: String
    var shortcut: String? = nil
    var active = false
    var disabled = false
    let action: () -> Void
    @State private var hovering = false
    @State private var showTip = false
    @State private var tipTask: Task<Void, Never>?

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .regular))
                .frame(width: 34, height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.white.opacity(active ? 0.16 : (hovering && !disabled ? 0.09 : 0)))
                )
                .opacity(disabled ? 0.35 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { inside in
            hovering = inside
            tipTask?.cancel()
            if inside {
                // Shottr-like: the tooltip only appears after the pointer rests for a moment.
                tipTask = Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    if !Task.isCancelled { withAnimation(.easeOut(duration: 0.12)) { showTip = true } }
                }
            } else {
                showTip = false
            }
        }
        .overlay(alignment: .topLeading) {
            if showTip {
                Tooltip(title: title, shortcut: shortcut)
                    .offset(x: -6, y: 38)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
        }
        .zIndex(showTip ? 10 : 0)
    }
}

struct Tooltip: View {
    let title: String
    let shortcut: String?

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            if let shortcut { Text(shortcut).foregroundStyle(.secondary) }
        }
        .font(.system(size: 13))
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color(white: 0.17))
                .overlay(Capsule(style: .continuous).stroke(Color.white.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
        )
    }
}
