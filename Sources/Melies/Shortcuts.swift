import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that opens the editor on the latest recording.
    static let openEditor = Self("openEditor", default: .init(.e, modifiers: [.command, .shift]))
    /// Global shortcut that starts, and stops, a screen recording.
    static let record = Self("record", default: .init(.six, modifiers: [.command, .shift]))
}

/// Shortcuts available inside the editor, shown in the Settings cheat sheet.
enum EditorShortcuts {
    static let all: [(keys: String, action: String)] = [
        ("Cmd + Shift + 6 (global)", "sc.record"),
        ("Cmd + Shift + E (global)", "sc.open"),
        ("Space", "sc.play"),
        ("I", "sc.in"),
        ("O", "sc.out"),
        ("Left / Right", "sc.frame"),
        ("Shift + Left / Right", "sc.frames10"),
        ("Cmd + C", "sc.copy"),
        ("Cmd + S", "sc.save"),
        ("Cmd + Shift + O", "sc.openfile"),
        ("Cmd + Shift + V", "sc.paste"),
        ("Esc", "sc.close"),
    ]
}

/// Display text for a shortcut. `Shortcut.description` shows the unshifted character, which is
/// "§" for the 6 key on an AZERTY keyboard; with Shift held it is really the digit.
@MainActor
func shortcutLabel(_ name: KeyboardShortcuts.Name) -> String {
    guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return "-" }
    let digits: [Int: String] = [
        kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
        kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",
    ]
    guard shortcut.modifiers.contains(.shift), let digit = digits[shortcut.carbonKeyCode] else {
        return shortcut.description
    }
    var text = ""
    if shortcut.modifiers.contains(.control) { text += "⌃" }
    if shortcut.modifiers.contains(.option) { text += "⌥" }
    text += "⇧"
    if shortcut.modifiers.contains(.command) { text += "⌘" }
    return text + digit
}
