import SwiftUI

/// The background behind the picture in the preview: gradient or solid, with the shadow of the rounded picture.
/// Same proportions as the export (margin, radius and shadow are fractions of the picture width, see FrameLayers).
struct FramePanel: View {
    let style: FrameStyle
    /// Where the picture is drawn (the area inside the margins).
    let video: CGRect

    var body: some View {
        let pad = CGFloat(style.padding) * video.width
        let panel = video.insetBy(dx: -pad, dy: -pad)
        let blur = CGFloat(style.shadow) * video.width * 0.05
        ZStack {
            Rectangle().fill(style.fill.swiftUI)
                .frame(width: panel.width, height: panel.height)
                .position(x: panel.midX, y: panel.midY)
            if style.shadow > 0.01 {
                RoundedRectangle(cornerRadius: CGFloat(style.radius) * video.width, style: .circular)
                    .fill(.black)
                    .frame(width: video.width, height: video.height)
                    .shadow(color: .black.opacity(0.55 * style.shadow + 0.1), radius: blur / 2, x: 0, y: blur * 0.45)
                    .position(x: video.midX, y: video.midY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Popover of the bottom bar: on/off, background swatches, margin / corner / shadow sliders.
struct FrameOptionsView: View {
    @Bindable var model: EditorModel

    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 8), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(L("frame.title"), isOn: $model.frame.enabled)
                .toggleStyle(.switch)
                .font(.headline)

            Group {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(FramePreset.all) { preset in
                        Button { model.frame.preset = preset.id } label: {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(preset.swiftUI)
                                .frame(width: 34, height: 34)
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.primary.opacity(0.18), lineWidth: 0.5))
                                .overlay {
                                    if model.frame.preset == preset.id {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 2.5).padding(-3)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .clickCursor()
                        .accessibilityLabel(L("frame.preset.\(preset.id)"))
                        .help(L("frame.preset.\(preset.id)"))
                    }
                }
                slider(L("frame.margin"), value: $model.frame.padding, range: FrameStyle.paddingRange)
                slider(L("frame.radius"), value: $model.frame.radius, range: FrameStyle.radiusRange)
                slider(L("frame.shadow"), value: $model.frame.shadow, range: 0...1)
            }
            .disabled(!model.frame.enabled)
            .opacity(model.frame.enabled ? 1 : 0.4)
        }
        .padding(16)
        .frame(width: 270)
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range)
        }
    }
}
