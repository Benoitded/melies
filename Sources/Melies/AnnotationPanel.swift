import SwiftUI

/// Settings of the selected annotation, in the floating panel: color, thickness or size, style, font.
struct AnnotationPanel: View {
    @ObservedObject var model: EditorModel
    @FocusState private var textFocused: Bool

    private let presets: [RGBA] = [.red, .yellow, .green, .blue, .white]

    var body: some View {
        if let a = model.selectedAnnotation {
            ToolPanel {
                colors(a)
                WedgeSlider(
                    value: Binding(get: { a.width }, set: { v in model.updateSelectedAnnotation { $0.width = v } }),
                    range: a.kind == .text ? 14...90 : (a.kind == .arrow ? 2...18 : 1...14)
                )
                .tip(a.kind == .text ? L("tip.size") : L("tip.width"), trailing: true)

                switch a.kind {
                case .arrow: arrowStyles(a)
                case .rect: rectStyles(a)
                case .text: textControls(a)
                }

                Button { model.deleteSelected() } label: {
                    Image(systemName: "trash").font(.system(size: 13)).foregroundStyle(.secondary)
                        .frame(width: 26, height: 26).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip(L("ann.delete"), trailing: true)
            }
            .onChange(of: textFocused) { _, focused in model.isEditingText = focused }
            .onChange(of: model.textFocusTick) { _, _ in takeFocusIfRequested() }
            .onAppear { takeFocusIfRequested() }
            .onDisappear { model.isEditingText = false }
        }
    }

    /// Focus the text field after the panel (and the field inside it) exist.
    private func takeFocusIfRequested() {
        guard model.wantsTextFocus else { return }
        model.wantsTextFocus = false
        DispatchQueue.main.async { textFocused = true }
    }

    private func colors(_ a: Annotation) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(presets.enumerated()), id: \.offset) { _, c in
                Button { model.updateSelectedAnnotation { $0.color = c } } label: {
                    Circle().fill(c.color)
                        .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.8))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(Color.accentColor, lineWidth: a.color == c ? 2 : 0).padding(-3))
                }
                .buttonStyle(.plain)
            }
            // Any color: a rainbow dot with the system color picker laid invisibly on top.
            ZStack {
                Circle().fill(AngularGradient(colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red], center: .center))
                    .overlay(Circle().stroke(Color.primary.opacity(0.25), lineWidth: 0.8))
                    .frame(width: 16, height: 16)
                ColorPicker("", selection: Binding(get: { a.color.color }, set: { v in model.updateSelectedAnnotation { $0.color = RGBA(v) } }), supportsOpacity: false)
                    .labelsHidden()
                    .opacity(0.02)
                    .frame(width: 22, height: 22)
                    .clipped()
            }
            .frame(width: 22, height: 22)
            .tip(L("tip.color"), trailing: true)
        }
    }

    private func arrowStyles(_ a: Annotation) -> some View {
        IconSegments(
            items: ArrowStyle.allCases.map { s in .init(value: s, tip: L("arrow.\(s.rawValue)"), icon: AnyView(ArrowGlyph(style: s))) },
            selection: a.arrow,
            onSelect: { v in model.updateSelectedAnnotation { $0.arrow = v } }
        )
    }

    private func rectStyles(_ a: Annotation) -> some View {
        IconSegments(
            items: RectStyle.allCases.map { s in .init(value: s, tip: L("rect.\(s.rawValue)"), icon: AnyView(RectGlyph(style: s))) },
            selection: a.rect,
            onSelect: { v in model.updateSelectedAnnotation { $0.rect = v } }
        )
    }

    @ViewBuilder
    private func textControls(_ a: Annotation) -> some View {
        TextField(L("ann.text"), text: Binding(get: { a.text }, set: { v in model.updateAnnotation(a.id) { $0.text = v } }))
            .textFieldStyle(.plain)
            .focused($textFocused)
            .font(.system(size: 13))
            .padding(.horizontal, 8)
            .frame(width: 150, height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.08)))
            .onSubmit { textFocused = false }

        Picker("", selection: Binding(get: { a.font }, set: { v in model.updateSelectedAnnotation { $0.font = v } })) {
            ForEach(FontStyle.allCases, id: \.self) { Text(L("font.\($0.rawValue)")).tag($0) }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 118)
        .tip(L("tip.fontstyle"), trailing: true)

        Button { model.updateSelectedAnnotation { $0.bold.toggle() } } label: {
            Image(systemName: "bold").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(a.bold ? Color.primary : Color.secondary)
                .frame(width: 28, height: 26)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(a.bold ? 0.13 : 0.06)))
        }
        .buttonStyle(.plain)
        .tip(L("tip.bold"), trailing: true)

        IconSegments(
            items: TextBox.allCases.map { b in .init(value: b, tip: L("box.\(b.rawValue)"), icon: AnyView(BoxGlyph(box: b))) },
            selection: a.box,
            onSelect: { v in model.updateSelectedAnnotation { $0.box = v } }
        )
    }
}

// MARK: Style icons

struct ArrowGlyph: View {
    let style: ArrowStyle

    var body: some View {
        Canvas { context, size in
            let y = size.height / 2
            var path = Path()
            switch style {
            case .block:
                path.move(to: CGPoint(x: 0, y: y - 1.5)); path.addLine(to: CGPoint(x: 9, y: y - 2.5)); path.addLine(to: CGPoint(x: 9, y: y - 5.5))
                path.addLine(to: CGPoint(x: size.width, y: y)); path.addLine(to: CGPoint(x: 9, y: y + 5.5)); path.addLine(to: CGPoint(x: 9, y: y + 2.5))
                path.addLine(to: CGPoint(x: 0, y: y + 1.5)); path.closeSubpath()
                context.fill(path, with: .foreground)
            case .line, .double:
                path.move(to: CGPoint(x: style == .double ? 3 : 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y))
                path.move(to: CGPoint(x: size.width - 5, y: y - 4)); path.addLine(to: CGPoint(x: size.width, y: y)); path.addLine(to: CGPoint(x: size.width - 5, y: y + 4))
                if style == .double {
                    path.move(to: CGPoint(x: 5, y: y - 4)); path.addLine(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: 5, y: y + 4))
                }
                context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: 18, height: 14)
    }
}

struct RectGlyph: View {
    let style: RectStyle

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style == .square ? 0.5 : 3.5, style: .continuous)
        ZStack {
            switch style {
            case .rounded, .square: shape.stroke(lineWidth: 1.6)
            case .soft: shape.fill(Color.primary.opacity(0.25)); shape.stroke(lineWidth: 1.6)
            case .solid: shape.fill(Color.primary)
            }
        }
        .frame(width: 17, height: 12)
    }
}

struct BoxGlyph: View {
    let box: TextBox

    var body: some View {
        Text("Aa")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(box == .badge ? Color(nsColor: .windowBackgroundColor) : Color.primary)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background {
                switch box {
                case .plain: Color.clear
                case .boxed: RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(Color.primary, lineWidth: 1.3)
                case .badge: RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.primary)
                }
            }
    }
}
