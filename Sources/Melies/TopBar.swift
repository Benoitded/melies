import SwiftUI

/// Shottr-style toolbar: actions, tools, then source info on the right.
struct TopBar: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var model: EditorModel
    @ObservedObject private var recorder = ScreenRecorder.shared

    var body: some View {
        HStack(spacing: 4) {
            BarButton(symbol: "doc.on.doc", title: L("tip.copy"), shortcut: "(⌘C)", disabled: model.busy) {
                Task { await model.copy() }
            }
            BarButton(symbol: "square.and.arrow.down", title: L("tip.save"), shortcut: "(⌘S)", disabled: model.busy) {
                Task { await model.save() }
            }
            divider
            BarButton(symbol: session.pinned ? "pin.fill" : "pin", title: L("tip.pin"), active: session.pinned) {
                session.pinned.toggle()
            }
            BarButton(symbol: "square.and.arrow.up", title: L("tip.share"), disabled: model.busy) {
                Task { await model.share(from: NSApp.keyWindow?.contentView) }
            }
            BarButton(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                      title: recorder.isRecording ? L("tip.stop") : L("tip.record"),
                      shortcut: "(⇧⌘6)", active: recorder.isRecording) {
                ScreenRecorder.shared.toggle()
            }
            divider
            BarButton(symbol: "scissors", title: L("tip.trim"), shortcut: "(I / O)") {}
            BarButton(symbol: "crop", title: L("tip.crop"), shortcut: "(C)", active: model.cropMode || model.cropRect != nil) {
                model.toggleCrop()
            }
            BarButton(symbol: "arrow.up.right", title: L("tip.arrow"), shortcut: L("tip.soon"), disabled: true) {}
            BarButton(symbol: "textformat", title: L("tip.text"), shortcut: L("tip.soon"), disabled: true) {}
            BarButton(symbol: "ruler", title: L("tip.measure"), shortcut: L("tip.soon"), disabled: true) {}
            BarButton(symbol: "rectangle", title: L("tip.rect"), shortcut: L("tip.soon"), disabled: true) {}
            BarButton(symbol: "viewfinder", title: L("tip.spotlight"), shortcut: L("tip.soon"), disabled: true) {}
            BarButton(symbol: "pencil", title: L("tip.pencil"), shortcut: L("tip.soon"), disabled: true) {}
            BarButton(symbol: "ellipsis", title: L("tip.more"), shortcut: L("tip.soon"), disabled: true) {}

            Spacer(minLength: 12)

            info(value: sizeText, label: model.croppedSize == nil ? L("info.source") : L("info.crop"))
            divider
            info(value: String(format: "%.1f s", max(model.end - model.start, 0)), label: L("info.duration"))
            divider
            info(value: fpsText, label: L("info.export"))
            divider
            info(value: "\(model.zoomPercent)%", label: L("info.zoom"))
        }
        .padding(.leading, 78) // room for the traffic lights
        .padding(.trailing, 16)
        .frame(height: 52)
    }

    private var sizeText: String {
        let size = model.croppedSize ?? model.sourceSize
        guard size.width > 0 else { return "..." }
        return "\(Int(size.width))×\(Int(size.height))"
    }

    private var fpsText: String {
        model.fps > 0 ? "\(Int(model.fps.rounded())) → 30 fps" : "..."
    }

    private var divider: some View {
        Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1, height: 22).padding(.horizontal, 6)
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
                        .fill(Color.primary.opacity(active ? 0.16 : (hovering && !disabled ? 0.09 : 0)))
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
                .fill(.regularMaterial)
                .overlay(Capsule(style: .continuous).stroke(Color.primary.opacity(0.14), lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        )
    }
}
