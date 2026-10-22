import SwiftUI

/// Format, size limit and resolution of exports. Used by copy, save, share and drag.
struct ExportOptionsView: View {
    @ObservedObject var model: EditorModel
    @AppStorage("exportFormat") private var format = "mp4"
    @AppStorage("exportMaxMB") private var maxMB = 0
    @AppStorage("exportMaxWidth") private var maxWidth = 1920
    @State private var custom = false

    private static let customTag = -1

    /// The presets, plus the current value when it was typed by hand (so the menu always shows what is set).
    private var choices: [Int] {
        let extra = maxMB > 0 && !ExportSettings.sizeChoices.contains(maxMB) ? [maxMB] : []
        return (ExportSettings.sizeChoices + extra).sorted()
    }

    /// The picker shows a preset, "no limit", or "Other..." when the value is typed by hand.
    private var sizeSelection: Binding<Int> {
        Binding(
            get: { custom ? Self.customTag : maxMB },
            set: { value in
                if value == Self.customTag { custom = true; if maxMB == 0 { maxMB = 20 } }
                else { custom = false; maxMB = value }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("exp.title")).font(.headline)

            Picker(L("exp.format"), selection: $format) {
                Text("MP4").tag("mp4")
                Text("HEVC").tag("hevc")
                Text("GIF").tag("gif")
            }
            .pickerStyle(.segmented)
            if format == "hevc" {
                Text(L("exp.hevc.note")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent(L("exp.size")) {
                Picker("", selection: sizeSelection) {
                    Text(L("exp.nolimit")).tag(0)
                    ForEach(choices, id: \.self) { Text("\($0) \(L("exp.mb"))").tag($0) }
                    Divider()
                    Text(L("exp.other")).tag(Self.customTag)
                }
                .labelsHidden()
                .frame(width: 130)
            }

            if sizeSelection.wrappedValue == Self.customTag {
                LabeledContent(" ") {
                    HStack(spacing: 6) {
                        TextField("", value: $maxMB, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                        Text(L("exp.mb")).foregroundStyle(.secondary)
                        Stepper("", value: $maxMB, in: 1...2000).labelsHidden()
                    }
                    .frame(width: 130, alignment: .trailing)
                }
            }

            LabeledContent(L("exp.width")) {
                Picker("", selection: $maxWidth) {
                    Text("360p").tag(640)
                    Text("480p").tag(854)
                    Text("720p").tag(1280)
                    Text("1080p").tag(1920)
                }
                .labelsHidden()
                .frame(width: 130)
            }

            Divider()
            Text(estimate).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 290)
        .task(id: "\(format)|\(maxMB)|\(maxWidth)|\(model.editRevision)|\(model.includeAudio)") {
            try? await Task.sleep(nanoseconds: 300_000_000) // let a burst of edits settle
            await model.measureEstimate()
        }
    }

    /// A rough size so the user knows what to expect before exporting.
    private var estimate: String {
        let settings = ExportSettings.current
        let seconds = max(model.end - model.start, 0.1)
        if settings.format == .gif {
            if let mb = settings.maxMegabytes { return L("exp.estimate.gif_limit", mb) }
            return L("exp.estimate.gif")
        }
        if let mb = settings.maxMegabytes { return L("exp.estimate.limit", mb) }
        guard let measured = model.measuredMB else { return L("exp.estimating") }
        // Ceiling: the bitrate asked of the encoder times the duration. Simple content stays under it.
        let base = model.baseSize.width > 0 ? model.baseSize : CGSize(width: 1280, height: 720)
        let scale = min(1, CGFloat(settings.maxWidth) / base.width)
        let canvas = CGSize(width: base.width * scale, height: base.height * scale)
        let audio = model.hasAudio && model.includeAudio
        let bitrate = settings.videoBitrate(seconds: seconds, canvas: canvas, hasAudio: audio)
        let ceiling = Double(bitrate) * seconds / 8 / 1_000_000 + (audio ? 0.016 * seconds : 0)
        if ceiling > measured * 1.25 {
            return L("exp.estimate.range", String(format: "%.1f", measured), String(format: "%.1f", ceiling))
        }
        return L("exp.estimate", String(format: "%.1f", max(measured, min(ceiling, measured * 1.1))))
    }
}
