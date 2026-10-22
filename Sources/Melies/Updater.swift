import AppKit
import Sparkle

/// Automatic updates with Sparkle. Releases are published by Scripts/release.sh, which signs each archive
/// and updates the appcast the app reads (SUFeedURL in Info.plist).
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController?

    /// Only a real app bundle can update itself: the bare binary used in tests has no feed.
    private init() {
        if Bundle.main.bundleURL.pathExtension == "app", Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        } else {
            controller = nil
        }
    }

    var isAvailable: Bool { controller != nil }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { objectWillChange.send(); controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    /// Before the first release is published the feed does not exist (GitHub answers 404): that is not an error
    /// for the user, it just means there is nothing newer, so say so instead of showing Sparkle's failure.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        guard let feed = (Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String).flatMap(URL.init(string:)) else {
            controller?.checkForUpdates(nil)
            return
        }
        Task {
            var request = URLRequest(url: feed)
            request.httpMethod = "HEAD"
            request.timeoutInterval = 8
            let status = (try? await URLSession.shared.data(for: request).1 as? HTTPURLResponse)?.statusCode
            if status == 404 {
                let alert = NSAlert()
                alert.messageText = L("upd.latest.title")
                alert.informativeText = L("upd.latest.text", versionLabel)
                alert.runModal()
            } else {
                controller?.checkForUpdates(nil)
            }
        }
    }

    var versionLabel: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }
}
