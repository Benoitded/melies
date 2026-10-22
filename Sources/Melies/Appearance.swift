import AppKit

/// App-wide theme: follow the system, or force light or dark.
enum Appearance {
    static let key = "appearance"

    static func apply() {
        switch UserDefaults.standard.string(forKey: key) ?? "system" {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}

extension NSWindow {
    /// Gives a glass window the same shape as the editor and Settings windows. In macOS 26 the corner radius
    /// follows the window's chrome: windows with a toolbar get the large radius, plain titled ones a smaller one,
    /// so an empty unified toolbar keeps every Méliès window the same shape. The glass fills the window and the
    /// system clips it, instead of drawing its own (different) corners.
    func useSharedGlassShape() {
        let toolbar = NSToolbar(identifier: "melies.glass")
        toolbar.showsBaselineSeparator = false
        self.toolbar = toolbar
        toolbarStyle = .unified
    }
}
