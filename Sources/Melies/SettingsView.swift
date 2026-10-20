import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage("watchedFolder") private var watchedFolder = ""

    var body: some View {
        Form {
            Section("Raccourci global") {
                KeyboardShortcuts.Recorder("Ouvrir l'éditeur", name: .openEditor)
            }
            Section("Dossier surveillé") {
                HStack {
                    Text(LatestRecording.watchedFolder().path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Choisir…") { chooseFolder() }
                }
            }
            Section("Raccourcis de l'éditeur") {
                ForEach(EditorShortcuts.all, id: \.keys) { item in
                    HStack {
                        Text(item.action)
                        Spacer()
                        Text(item.keys).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 520)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url { watchedFolder = url.path }
    }
}
