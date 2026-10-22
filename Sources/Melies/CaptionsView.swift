import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

/// Captions of the open video (session only): the lines, how they look, and the state of a running generation.
@MainActor
@Observable
final class CaptionsModel {
    var lines: [Caption] = [] { didSet { onChange?() } }
    var style = CaptionStyle() { didSet { onChange?() } }
    /// Burn the captions into the export (and show them in the preview).
    var showInExport = true { didSet { onChange?() } }

    var locales: [Locale] = []
    var localeID: String?
    var localesLoaded = false
    var generating = false
    var progress = 0.0
    var message: String?

    @ObservationIgnored var onChange: (() -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    var locale: Locale? { locales.first { $0.identifier == localeID } }

    /// What the export draws, or nil when captions are off or empty.
    var plan: CaptionPlan? { showInExport && !lines.isEmpty ? CaptionPlan(captions: lines, style: style) : nil }

    func loadLocales() async {
        guard !localesLoaded else { return }
        locales = await CaptionGenerator.installedLocales()
        localeID = CaptionGenerator.defaultLocale(among: locales)?.identifier
        localesLoaded = true
        if locales.isEmpty { message = L("cap.err.nolocale") }
    }

    func generate(asset: AVAsset) {
        guard !generating, let locale else { return }
        generating = true
        progress = 0
        message = nil
        task = Task {
            do {
                let words = try await CaptionGenerator.generate(asset: asset, locale: locale) { fraction in
                    Task { @MainActor in self.progress = fraction }
                }
                lines = CaptionLayout.group(words)
                message = lines.isEmpty ? L("cap.err.nospeech") : nil
            } catch is CancellationError {
                message = L("cap.cancelled")
            } catch {
                message = error.localizedDescription
            }
            generating = false
        }
    }

    func cancel() { task?.cancel() }

    func update(_ id: UUID, _ change: (inout Caption) -> Void) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        var line = lines[i]
        change(&line)
        line.start = max(line.start, 0)
        line.end = max(line.end, line.start + 0.1)
        lines[i] = line
    }

    func delete(_ id: UUID) { lines.removeAll { $0.id == id } }

    /// Writes the captions of the kept range as an .srt file (times start at the trim start).
    func exportSRT(start: Double, end: Double, suggestedName: String, directory: URL) -> String? {
        let kept = CaptionLayout.forTrim(lines, start: start, end: end)
        guard !kept.isEmpty else { return L("cap.srt.empty") }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        panel.nameFieldStringValue = suggestedName + ".srt"
        panel.directoryURL = directory
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try CaptionLayout.srt(kept).write(to: url, atomically: true, encoding: .utf8)
            return L("cap.srt.saved", url.lastPathComponent)
        } catch {
            return L("status.fail", error.localizedDescription)
        }
    }
}

/// Bottom bar button: opens the captions panel.
struct CaptionsButton: View {
    var model: EditorModel
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Image(systemName: model.captions.lines.isEmpty ? "captions.bubble" : "captions.bubble.fill")
                .font(.system(size: 12))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.glass)
        .clickCursor()
        .buttonBorderShape(.circle)
        .tip(L("cap.title"), trailing: true)
        .popover(isPresented: $open, arrowEdge: .top) { CaptionsView(model: model) }
    }
}

/// Captions drawn over the picture in the preview, with the same code as the export.
struct CaptionOverlay: View {
    var model: EditorModel
    let video: CGRect

    var body: some View {
        let captions = model.captions
        Canvas { context, _ in
            guard captions.showInExport, let line = CaptionLayout.visible(captions.lines, at: model.current) else { return }
            context.withCGContext { cg in
                cg.clip(to: video)
                CaptionRenderer.draw(line.text, style: captions.style, in: cg, area: video)
            }
        }
        .allowsHitTesting(false)
    }
}

struct CaptionsView: View {
    var model: EditorModel
    private var captions: CaptionsModel { model.captions }

    var body: some View {
        @Bindable var captions = model.captions
        VStack(alignment: .leading, spacing: 12) {
            Toggle(L("cap.show"), isOn: $captions.showInExport)
                .toggleStyle(.switch)
                .font(.headline)

            if !model.hasAudio {
                Text(L("cap.err.noaudio")).font(.callout).foregroundStyle(.secondary)
            } else {
                generator(captions: $captions)
            }

            if let message = captions.message {
                Text(message).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if !captions.lines.isEmpty {
                styleControls(style: $captions.style)
                Divider()
                list
                HStack {
                    Button(L("cap.srt")) {
                        captions.message = captions.exportSRT(start: model.start, end: model.end,
                                                              suggestedName: model.url.deletingPathExtension().lastPathComponent,
                                                              directory: model.url.deletingLastPathComponent())
                    }
                    .buttonStyle(.glass).clickCursor()
                    Spacer()
                    Button(L("cap.clear"), role: .destructive) { captions.lines = [] }
                        .buttonStyle(.glass).clickCursor()
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .task { await captions.loadLocales() }
    }

    private func generator(captions: Bindable<CaptionsModel>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !captions.wrappedValue.locales.isEmpty {
                Picker(L("cap.language"), selection: captions.localeID) {
                    ForEach(captions.wrappedValue.locales, id: \.identifier) { locale in
                        Text(CaptionGenerator.name(locale)).tag(Optional(locale.identifier))
                    }
                }
                .disabled(captions.wrappedValue.generating)
            }
            HStack {
                if captions.wrappedValue.generating {
                    ProgressView(value: captions.wrappedValue.progress).progressViewStyle(.linear)
                    Button(L("cap.cancel")) { captions.wrappedValue.cancel() }.buttonStyle(.glass).clickCursor()
                } else {
                    Button(captions.wrappedValue.lines.isEmpty ? L("cap.generate") : L("cap.regenerate")) {
                        captions.wrappedValue.generate(asset: model.asset)
                    }
                    .buttonStyle(.glassProminent).clickCursor()
                    .disabled(captions.wrappedValue.locale == nil)
                    Text(L("cap.local")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func styleControls(style: Binding<CaptionStyle>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("cap.position"), selection: style.position) {
                Text(L("cap.position.bottom")).tag(CaptionStyle.Position.bottom)
                Text(L("cap.position.top")).tag(CaptionStyle.Position.top)
            }.pickerStyle(.segmented)
            Picker(L("cap.size"), selection: style.size) {
                Text("S").tag(CaptionStyle.Size.small)
                Text("M").tag(CaptionStyle.Size.medium)
                Text("L").tag(CaptionStyle.Size.large)
            }.pickerStyle(.segmented)
            Toggle(L("cap.background"), isOn: style.background)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(captions.lines) { line in
                    CaptionRow(model: model, line: line)
                }
            }
        }
        .frame(maxHeight: 240)
    }
}

private struct CaptionRow: View {
    var model: EditorModel
    let line: Caption

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(spacing: 2) {
                time(line.start) { value in model.captions.update(line.id) { $0.start = value } }
                time(line.end) { value in model.captions.update(line.id) { $0.end = value } }
            }
            TextField("", text: Binding(get: { line.text }, set: { text in model.captions.update(line.id) { $0.text = text } }), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
            Button { model.captions.delete(line.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).clickCursor()
                .foregroundStyle(.secondary)
                .tip(L("cap.delete"), trailing: true)
        }
    }

    private func time(_ value: Double, set: @escaping (Double) -> Void) -> some View {
        TextField("", value: Binding(get: { value }, set: set), format: .number.precision(.fractionLength(1)))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11).monospacedDigit())
            .frame(width: 52)
    }
}
