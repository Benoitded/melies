import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// Global shortcut that opens the editor on the latest recording.
    static let openEditor = Self("openEditor", default: .init(.e, modifiers: [.command, .shift]))
}

/// Shortcuts available inside the editor, shown in the Settings cheat sheet.
enum EditorShortcuts {
    static let all: [(keys: String, action: String)] = [
        ("Space", "Lecture / pause"),
        ("I", "Point d'entree (trim)"),
        ("O", "Point de sortie (trim)"),
        ("Left / Right", "Image precedente / suivante"),
        ("Shift + Left / Right", "10 images"),
        ("Cmd + C", "Copier le MP4 Twitter"),
        ("Cmd + S", "Enregistrer le MP4 Twitter"),
        ("Cmd + Shift + O", "Ouvrir un fichier"),
        ("Cmd + Shift + V", "Charger depuis le presse-papiers"),
        ("Esc", "Fermer"),
    ]
}
