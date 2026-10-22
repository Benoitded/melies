import SwiftUI

/// Format, size limit and resolution of exports. Used by copy, save, share and drag.
struct ExportOptionsView: View {
    @ObservedObject var model: EditorModel
    @AppStorage("exportFormat") private var format = "mp4"
    @AppStorage("exportMaxMB") private var maxMB = 0
    @AppStorage("exportMaxWidth") private var maxWidth = 1920

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("exp.title")).font(.headline)

            Picker(L("exp.format"), selection: $format) {
                Text("MP4").tag("mp4")
                Text("GIF").tag("gif")
            }
            .pickerStyle(.segmented)

            LabeledContent(L("exp.size")) {
                Picker("", selection: $maxMB) {
                    Text(L("exp.nolimit")).tag(0)
                    ForEach(ExportSettings.sizeChoices, id: \.self) { Text("\($0) \(L("exp.mb"))").tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
            }

            LabeledContent(L("exp.width")) {
                Picker("", selection: $maxWidth) {
                    Text("720p").tag(1280)
                    Text("1080p").tag(1920)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
            }

            Divider()
            Text(estimate).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 290)
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
        let base = model.baseSize.width > 0 ? model.baseSize : CGSize(width: 1280, height: 720)
        let scale = min(1, CGFloat(settings.maxWidth) / base.width)
        let canvas = CGSize(width: base.width * scale, height: base.height * scale)
        let bitrate = settings.videoBitrate(seconds: seconds, canvas: canvas, hasAudio: model.hasAudio && model.includeAudio)
        let megabytes = Double(bitrate) * seconds / 8 / 1_000_000 + (model.hasAudio && model.includeAudio ? 0.016 * seconds : 0)
        return L("exp.estimate", String(format: "%.1f", megabytes))
    }
}
