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
