import AppKit
import ScreenCaptureKit

/// Records a dragged region of the screen to a .mov in the watched folder, then opens the editor on it.
@MainActor
final class ScreenRecorder: NSObject, ObservableObject, SCStreamDelegate, SCRecordingOutputDelegate {
    static let shared = ScreenRecorder()

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0

    private var stream: SCStream?
    private var outputURL: URL?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var startedAt = Date()
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var busy = false
    private var overlay: RecordingOverlay?

    /// Same shortcut starts and stops.
    func toggle() {
        guard !busy else { return }
        if isRecording { Task { await stop() } } else { Task { await begin() } }
    }

    // MARK: Start

    private func begin() async {
        busy = true
        defer { busy = false }

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            alert(L("rec.perm.title"),
                  L("rec.perm.text"))
            return
        }
        guard let selection = await RegionSelector.select() else { return }
        overlay = RecordingOverlay(screen: selection.screen, region: selection.rect)
        try? await Task.sleep(for: .milliseconds(220)) // let the selector disappear before capturing

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            let id = selection.screen.deviceDescription[key] as? CGDirectDisplayID
            guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else {
                closeOverlay(); alert(L("rec.nodisplay"), ""); return
            }

            let scale = selection.screen.backingScaleFactor
            let config = SCStreamConfiguration()
            config.sourceRect = selection.rect
            config.width = even(selection.rect.width * scale)
            config.height = even(selection.rect.height * scale)
            config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            config.showsCursor = true
            config.capturesAudio = false

            let url = Self.newOutputURL()
            let recordingConfig = SCRecordingOutputConfiguration()
            recordingConfig.outputURL = url
            recordingConfig.videoCodecType = .h264
            recordingConfig.outputFileType = .mov
            let output = SCRecordingOutput(configuration: recordingConfig, delegate: self)

            // Keep every Méliès window (dimming overlay, editor, menu bar button) out of the video.
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let own = content.windows.filter { $0.owningApplication?.processID == ownPID }
            let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: own), configuration: config, delegate: self)
            try stream.addRecordingOutput(output)
            try await stream.startCapture()

            self.stream = stream
            self.outputURL = url
            startedAt = Date()
            elapsed = 0
            isRecording = true
            showStatusItem()
        } catch {
            closeOverlay()
            alert(L("rec.failed"), error.localizedDescription)
        }
    }

    // MARK: Stop

    private func stop() async {
        guard let stream, isRecording else { return }
        closeOverlay()
        busy = true
        defer { busy = false }

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishContinuation = continuation
            Task { try? await stream.stopCapture() }
            // Safety net so a missing delegate callback can never hang the app.
            Task {
                try? await Task.sleep(for: .seconds(6))
                self.resumeFinish()
            }
        }

        self.stream = nil
        isRecording = false
        hideStatusItem()
        if let url = outputURL, FileManager.default.fileExists(atPath: url.path) {
            if UserDefaults.standard.object(forKey: "openEditorAfterRecording") as? Bool ?? true {
                EditorWindowController.shared.open(url)
            } else {
                Toast.show(L("toast.recorded"))
            }
        }
    }

    private func resumeFinish() {
        finishContinuation?.resume()
        finishContinuation = nil
    }

    // MARK: Delegates

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in self.resumeFinish() }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in self.resumeFinish() }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in self.resumeFinish() }
    }

    // MARK: Status item (the red stop button in the menu bar)

    private func showStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(stopFromButton)
        statusItem = item
        updateStatusTitle()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.elapsed = Date().timeIntervalSince(self.startedAt)
                self.updateStatusTitle()
            }
        }
    }

    private func updateStatusTitle() {
        let total = Int(elapsed)
        let text = String(format: "■  %d:%02d", total / 60, total % 60)
        // A red pill with white text reads as a button: click it to stop.
        statusItem?.button?.wantsLayer = true
        statusItem?.button?.layer?.backgroundColor = NSColor.systemRed.cgColor
        statusItem?.button?.layer?.cornerRadius = 6
        statusItem?.button?.attributedTitle = NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold),
        ])
        statusItem?.button?.toolTip = L("tip.stop")
    }

    private func hideStatusItem() {
        timer?.invalidate()
        timer = nil
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }

    @objc private func stopFromButton() { toggle() }

    // MARK: Helpers

    private func closeOverlay() {
        overlay?.close()
        overlay = nil
    }

    private func even(_ value: CGFloat) -> Int { max(2, Int((value / 2).rounded()) * 2) }

    private static func newOutputURL() -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return LatestRecording.watchedFolder().appendingPathComponent("Melies Recording \(formatter.string(from: Date())).mov")
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}
