import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @AppStorage("watchedFolder") private var watchedFolder = ""
    @AppStorage("closeAfterAction") private var closeAfterAction = true

    var body: some View {
        Form {
            Section(L("settings.section.global")) {
                KeyboardShortcuts.Recorder(L("settings.record"), name: .record)
                KeyboardShortcuts.Recorder(L("settings.open_editor"), name: .openEditor)
            }
            Section(L("settings.section.folder")) {
                HStack {
                    Text(LatestRecording.watchedFolder().path).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button(L("settings.choose")) { chooseFolder() }
                }
            }
            Section {
                Toggle(L("settings.close_after"), isOn: $closeAfterAction)
            }
            Section(L("settings.section.editor")) {
                ForEach(EditorShortcuts.all, id: \.keys) { item in
                    HStack {
                        Text(L(item.action))
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
