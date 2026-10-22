import SwiftUI

// MARK: Tooltip with a hover delay

/// Appears after the pointer rests on the control, like Shottr's.
struct DelayedTip: ViewModifier {
    let title: String
    let shortcut: String?
    /// Anchor the tooltip to the right edge of the control, so it grows leftwards near the window edge.
    let trailing: Bool
    /// When the control tracks hover itself (an AppKit view), pass its state here.
    var hover: Bool?

    @State private var show = false
    @State private var task: Task<Void, Never>?

    private func hoverChanged(_ inside: Bool) {
        task?.cancel()
        if inside {
            task = Task {
                try? await Task.sleep(for: .milliseconds(450))
                if !Task.isCancelled { withAnimation(.easeOut(duration: 0.12)) { show = true } }
            }
        } else {
            show = false
        }
    }

    func body(content: Content) -> some View {
        content
            .onHover { inside in if hover == nil { hoverChanged(inside) } }
            .onChange(of: hover ?? false) { _, inside in if hover != nil { hoverChanged(inside) } }
            .overlay(alignment: trailing ? .topTrailing : .topLeading) {
                if show {
                    Tooltip(title: title, shortcut: shortcut)
                        .offset(x: trailing ? 6 : -6, y: 36)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                }
            }
            .zIndex(show ? 10 : 0)
    }
}

extension View {
    func tip(_ title: String, shortcut: String? = nil, trailing: Bool = false, hovering: Bool? = nil) -> some View {
        modifier(DelayedTip(title: title, shortcut: shortcut, trailing: trailing, hover: hovering))
    }
}

// MARK: Floating tool settings panel (top right of the canvas, like Shottr)

struct ToolPanel<Content: View>: View {
    @AppStorage("toolPanelCollapsed") private var collapsed = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.snappy(duration: 0.2)) { collapsed.toggle() }
            } label: {
                Image(systemName: collapsed ? "chevron.right" : "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !collapsed { content.transition(.opacity) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// Icon buttons in one rounded group; the selected one is highlighted.
struct IconSegments<Value: Hashable>: View {
    struct Item {
        let value: Value
        let tip: String
        let icon: AnyView
    }

    let items: [Item]
    let selection: Value?
    let onSelect: (Value) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let selected = selection == item.value
                Button { onSelect(item.value) } label: {
                    item.icon
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(width: 30, height: 26)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.primary.opacity(selected ? 0.13 : 0))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tip(item.tip, trailing: true)
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
    }
}

/// Slider drawn as a wedge that grows from thin to thick, as in Shottr's thickness control.
struct WedgeSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var width: CGFloat = 108

    private let knob: CGFloat = 20

    var body: some View {
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        ZStack(alignment: .leading) {
            Wedge().fill(Color.primary.opacity(0.07))
            Wedge().stroke(Color.primary.opacity(0.22), lineWidth: 0.8)
            Circle()
                .fill(Color.white)
                .overlay(Circle().stroke(Color.black.opacity(0.14), lineWidth: 0.8))
                .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                .frame(width: knob, height: knob)
                .offset(x: (width - knob) * CGFloat(min(max(t, 0), 1)))
        }
        .frame(width: width, height: 24)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
                let f = min(max(Double((drag.location.x - knob / 2) / (width - knob)), 0), 1)
                value = range.lowerBound + f * (range.upperBound - range.lowerBound)
            }
        )
    }
}

private struct Wedge: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let thin: CGFloat = 4, thick: CGFloat = 15
        p.move(to: CGPoint(x: rect.minX + 2, y: rect.midY - thin / 2))
        p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY - thick / 2))
        p.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.midY + thick / 2))
        p.addLine(to: CGPoint(x: rect.minX + 2, y: rect.midY + thin / 2))
        p.closeSubpath()
        return p
    }
}

/// Small drawing of an easing curve, used as the icon of each animation style.
struct EaseGlyph: View {
    let ease: ZoomEase

    var body: some View {
        Path { p in
            let w: CGFloat = 16, h: CGFloat = 11
            for i in 0...24 {
                let u = Double(i) / 24
                let point = CGPoint(x: CGFloat(u) * w, y: h - CGFloat(ease.apply(u)) * h * 0.85)
                if i == 0 { p.move(to: point) } else { p.addLine(to: point) }
            }
        }
        .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
        .frame(width: 16, height: 11)
        .offset(y: 1)
    }
}
