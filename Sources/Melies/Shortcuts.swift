import AppKit
import Carbon.HIToolbox
import KeyboardShortcuts
import SwiftUI

extension KeyboardShortcuts.Name {
    /// Global shortcut that opens the editor on the latest recording.
    static let openEditor = Self("openEditor", default: .init(.e, modifiers: [.command, .shift]))
    /// Global shortcut that starts, and stops, a screen recording.
    static let record = Self("record", default: .init(.six, modifiers: [.command, .shift]))
}

/// Shortcuts available inside the editor, shown in the Settings cheat sheet.
enum EditorShortcuts {
    static let all: [(keys: String, action: String)] = [
        ("␣", "sc.play"),
        ("I", "sc.in"),
        ("O", "sc.out"),
        ("←  →", "sc.frame"),
        ("⇧←  ⇧→", "sc.frames10"),
        ("C", "sc.crop"),
        ("↩", "sc.crop_confirm"),
        ("⌘C", "sc.copy"),
        ("⌘S", "sc.save"),
        ("⌘O", "sc.openfile"),
        ("⇧⌘V", "sc.paste"),
        ("⌘,", "sc.settings"),
        ("⌘W  Esc", "sc.close"),
    ]
}

/// Top-row digit keys. On an AZERTY keyboard these keys type a symbol unless Shift is held.
private let digitKeys: [Int: Character] = [
    kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3", kVK_ANSI_4: "4", kVK_ANSI_5: "5",
    kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9", kVK_ANSI_0: "0",
]

/// Display text for a shortcut. `Shortcut.description` shows the unshifted character, which is
/// "§" for the 6 key on an AZERTY keyboard; with Shift held it is really the digit.
@MainActor
func shortcutLabel(_ name: KeyboardShortcuts.Name) -> String {
    guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return "-" }
    guard shortcut.modifiers.contains(.shift), let digit = digitKeys[shortcut.carbonKeyCode] else {
        return shortcut.description
    }
    var text = ""
    if shortcut.modifiers.contains(.control) { text += "⌃" }
    if shortcut.modifiers.contains(.option) { text += "⌥" }
    text += "⇧"
    if shortcut.modifiers.contains(.command) { text += "⌘" }
    return text + String(digit)
}

/// The same shortcut as a SwiftUI one, so a menu item shows it on the right like Shottr does.
@MainActor
func swiftUIShortcut(_ name: KeyboardShortcuts.Name) -> KeyboardShortcut? {
    guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return nil }
    let key = digitKeys[shortcut.carbonKeyCode] ?? shortcut.nsMenuItemKeyEquivalent?.first
    guard let key else { return nil }
    var modifiers: SwiftUI.EventModifiers = []
    if shortcut.modifiers.contains(.command) { modifiers.insert(.command) }
    if shortcut.modifiers.contains(.shift) { modifiers.insert(.shift) }
    if shortcut.modifiers.contains(.option) { modifiers.insert(.option) }
    if shortcut.modifiers.contains(.control) { modifiers.insert(.control) }
    return KeyboardShortcut(KeyEquivalent(key), modifiers: modifiers)
}
