import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Holds the video currently open in the editor window.
@MainActor
final class EditorSession: ObservableObject {
    @Published var model: EditorModel?
    @Published var pinned = false { didSet { onPinChange?(pinned) } }
    var onPinChange: ((Bool) -> Void)?

    func open(_ url: URL) {
        model?.player.pause()
        model = EditorModel(url: url)
    }

    func openLatest() {
        if let url = LatestRecording.find() { open(url) }
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.allowsMultipleSelection = false
        panel.directoryURL = LatestRecording.watchedFolder()
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func loadFromPasteboard() {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        if let url = urls.first(where: { LatestRecording.videoExtensions.contains($0.pathExtension.lowercased()) }) {
            open(url)
        }
    }
}
