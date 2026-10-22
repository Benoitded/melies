import SwiftUI

/// Pointer styles that say what a spot does, so the cursor itself explains the action:
/// - pointing hand: click (buttons, icons, color dots, segments)
/// - open hand / closed hand: grab and move (annotations, crop, zoom region, timeline bars, diamonds, the video when zoomed)
/// - resize arrows: drag an edge or corner (crop, zoom region, annotation corners, trim handles)
/// - crosshair: drag to draw (arrow, rectangle, spotlight, blur tools); text bar: click to place text
extension View {
    /// A click target.
    func clickCursor(_ enabled: Bool = true) -> some View {
        pointerStyle(enabled ? .link : nil)
    }

    /// Something to grab: open hand, closed while it is being dragged.
    func grabCursor(dragging: Bool = false) -> some View {
        pointerStyle(dragging ? .grabActive : .grabIdle)
    }
}

extension PointerStyle {
    /// Diagonal resize cursor for corner `index` in the order top-left, top-right, bottom-left, bottom-right.
    static func corner(_ index: Int) -> PointerStyle {
        switch index {
        case 0: return .frameResize(position: .topLeading)
        case 1: return .frameResize(position: .topTrailing)
        case 2: return .frameResize(position: .bottomLeading)
        default: return .frameResize(position: .bottomTrailing)
        }
    }
}
