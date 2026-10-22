import SwiftUI
import UniformTypeIdentifiers

/// Shottr-style toolbar: actions, tools, then source info on the right.
struct TopBar: View {
    @ObservedObject var session: EditorSession
    @ObservedObject var model: EditorModel
    @ObservedObject private var recorder = ScreenRecorder.shared

    var body: some View {
        HStack(spacing: 4) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    group {
            BarButton(symbol: "doc.on.doc", title: L("tip.copy"), shortcut: "(⌘C)", disabled: model.busy) {
                Task { await model.copy() }
            }
            BarButton(symbol: "square.and.arrow.down", title: L("tip.save"), shortcut: "(⌘S)", disabled: model.busy) {
                Task { await model.save() }
            }
            DragHandle(model: model)
                    }
                    group {
            BarButton(symbol: session.pinned ? "pin.fill" : "pin", title: L("tip.pin"), active: session.pinned) {
                session.pinned.toggle()
            }
            BarButton(symbol: "square.and.arrow.up", title: L("tip.share"), disabled: model.busy) {
                Task { await model.share(from: NSApp.keyWindow?.contentView) }
            }
            BarButton(symbol: "rectangle.on.rectangle", title: L("tip.combine")) {
                CombineWindowController.shared.show(current: model.url)
            }
            BarButton(symbol: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                      title: recorder.isRecording ? L("tip.stop") : L("tip.record"),
                      shortcut: "(⇧⌘6)", active: recorder.isRecording) {
                ScreenRecorder.shared.toggle()
            }
                    }
                    group {
                        BarButton(symbol: "cursorarrow", title: L("tip.select"), shortcut: "(V)", active: model.tool == .select) {
                            model.setTool(.select)
                        }
                        BarButton(symbol: "arrow.up.right", title: L("tip.arrow"), shortcut: "(A)", active: model.tool == .arrow) {
                            model.setTool(.arrow)
                        }
                        BarButton(symbol: "textformat", title: L("tip.text"), shortcut: "(T)", active: model.tool == .text) {
                            model.setTool(.text)
                        }
                        BarButton(symbol: "rectangle", title: L("tip.rect"), shortcut: "(R)", active: model.tool == .rect) {
                            model.setTool(.rect)
                        }
                        BarButton(symbol: "circle.lefthalf.filled.inverse", title: L("tip.spotlight"), shortcut: "(S)", active: model.tool == .spotlight) {
                            model.setTool(.spotlight)
                        }
                        BarButton(symbol: "squareshape.split.3x3", title: L("tip.blur"), shortcut: "(B)", active: model.tool == .blur) {
                            model.setTool(.blur)
                        }
                        BarButton(symbol: "scissors", title: L("tip.trim"), shortcut: "(I / O)") {}
                        BarButton(symbol: "crop", title: L("tip.crop"), shortcut: "(C)", active: model.cropMode || model.cropRect != nil) {
                            model.toggleCrop()
                        }
                        BarButton(symbol: "cursorarrow.click.2", title: L(model.hasClicks ? "tip.clicks" : "tip.clicks.none"), active: model.showClicks && model.hasClicks, dimmed: !model.hasClicks) {
                            // No recorded clicks: the button is dimmed, and a click says why instead of doing nothing.
                            guard model.hasClicks else { Toast.show(L("toast.noclicks")); return }
                            model.showClicks.toggle()
                            UserDefaults.standard.set(model.showClicks, forKey: Pref.showClicks)
                        }
                        BarButton(symbol: "plus.magnifyingglass", title: L("tip.zoomanim"), shortcut: "(Z)", active: !model.zoomPoints.isEmpty) {
                            model.addZoom()
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            info(value: sizeText, label: model.croppedSize == nil ? L("info.source") : L("info.crop"))
            divider
            info(value: String(format: "%.1f s", max(model.end - model.start, 0)), label: L("info.duration"))
            divider
            info(value: "\(model.zoomPercent)%", label: L("info.zoom"))
        }
        .padding(.leading, 88) // room for the traffic lights
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

    /// One Liquid Glass capsule holding a related set of buttons.
    private func group<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) { content() }
            .padding(.horizontal, 4)
            .frame(height: 38)
            .glassEffect(.regular, in: .capsule)
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
    /// Looks unavailable but still answers a click (to say why it does nothing), unlike `disabled`.
    var dimmed = false
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
                    Capsule()
                        .fill(active ? Color.accentColor.opacity(0.3) : Color.primary.opacity(hovering && !disabled ? 0.1 : 0))
                )
                .opacity(disabled || dimmed ? 0.35 : 1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .clickCursor(!disabled)
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
        .glassEffect(.regular, in: .capsule)
    }
}

/// Grab it and drop the optimized MP4 into any app (a message, a mail, the Finder, a web page).
/// The handle sits in the title bar, where a mouse press normally moves the whole window, so the press and
/// the drag are handled by an AppKit view that refuses to move the window and starts a real file drag.
struct DragHandle: View {
    @ObservedObject var model: EditorModel
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 3) {
            grips
            Image(systemName: "doc").font(.system(size: 17, weight: .regular))
            grips
        }
        .frame(width: 50, height: 30)
        .background(Capsule().fill(Color.primary.opacity(hovering ? 0.1 : 0)))
        .overlay { DragSourceView(model: model, hovering: $hovering) }
        .pointerStyle(.grabIdle)
        .tip(L("tip.drag"), hovering: hovering)
    }

    /// Two columns of three dots, like a grab handle.
    private var grips: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 2.5) {
                    ForEach(0..<3, id: \.self) { _ in Circle().frame(width: 2.2, height: 2.2) }
                }
            }
        }
        .foregroundStyle(.tertiary)
    }
}

/// Invisible AppKit view over the handle: tracks hover, never moves the window, and begins the file drag.
private struct DragSourceView: NSViewRepresentable {
    let model: EditorModel
    @Binding var hovering: Bool

    func makeNSView(context: Context) -> DragSourceNSView {
        let view = DragSourceNSView()
        view.model = model
        view.onHover = { hovering = $0 }
        return view
    }

    func updateNSView(_ view: DragSourceNSView, context: Context) {
        view.model = model
        view.onHover = { hovering = $0 }
    }
}

private final class DragSourceNSView: NSView, NSDraggingSource, NSFilePromiseProviderDelegate {
    var model: EditorModel?
    var onHover: ((Bool) -> Void)?
    private var pressEvent: NSEvent?

    /// The title bar moves the window on a mouse press; this view must not.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?(true); model?.prepareDragFile() }
    override func mouseExited(with event: NSEvent) { onHover?(false) }
    override func mouseDown(with event: NSEvent) { pressEvent = event; model?.prepareDragFile() }

    override func mouseDragged(with event: NSEvent) {
        guard let press = pressEvent, model != nil,
              hypot(event.locationInWindow.x - press.locationInWindow.x, event.locationInWindow.y - press.locationInWindow.y) > 3
        else { return }
        pressEvent = nil

        // A real file when it is ready (works everywhere); otherwise a promise, exported when the drop asks for it.
        let writer: NSPasteboardWriting
        if let file = model?.readyDragFile() {
            writer = file as NSURL
        } else {
            writer = NSFilePromiseProvider(fileType: ExportSettings.current.contentType.identifier, delegate: self)
        }
        let item = NSDraggingItem(pasteboardWriter: writer)
        let size = NSSize(width: 140, height: 90)
        let origin = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: origin.x - size.width / 2, y: origin.y - size.height / 2, width: size.width, height: size.height),
                              contents: previewImage(size))
        beginDraggingSession(with: [item], event: press, source: self)
    }

    /// The first frame of the video, with rounded corners.
    private func previewImage(_ size: NSSize) -> NSImage {
        let frame = model?.thumbnails.first
        return NSImage(size: size, flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
            path.addClip()
            NSColor.black.setFill()
            rect.fill()
            frame?.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.white.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }

    // MARK: NSDraggingSource

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }

    /// Like Shottr: while the file is being dragged the editor steps aside, so it never covers where the file is
    /// going (the app behind it, the desktop, a chat window). It comes back when the drag ends, wherever it ends.
    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        guard let window else { return }
        window.ignoresMouseEvents = true // transparent to the pointer too, or it would still catch the drop
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 0
        }
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let window else { return }
        window.ignoresMouseEvents = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            window.animator().alphaValue = 1
        }
        if operation != [] { model?.status = L("status.dragged") }
    }

    // MARK: NSFilePromiseProviderDelegate (the export runs only when the destination asks for the file)

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        let name = model?.url.deletingPathExtension().lastPathComponent ?? "video"
        return name + "." + ExportSettings.current.fileExtension
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void) {
        guard let model else { completionHandler(ExportError.noVideoTrack); return }
        Task { @MainActor in
            let ok = await model.export(to: url)
            if ok { model.status = L("status.dragged") }
            completionHandler(ok ? nil : ExportError.noVideoTrack)
        }
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue { .main }
}
