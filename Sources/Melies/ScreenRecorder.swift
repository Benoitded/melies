import AppKit
import AVFoundation
import ScreenCaptureKit

/// Records a dragged region of the screen to a .mov in the watched folder, then opens the editor on it.
@MainActor
final class ScreenRecorder: NSObject, ObservableObject, SCStreamDelegate, SCRecordingOutputDelegate {
    static let shared = ScreenRecorder()

    @Published private(set) var isRecording = false
    /// Identity of the recording in progress (manual or AI), nil when none. An AI client may only stop its own.
    private(set) var currentRecordingID: UUID?
    @Published private(set) var elapsed: TimeInterval = 0

    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?
    /// Tags the pending stop so a late callback or safety timer of an older stop cannot resume a newer one.
    private var finishToken = 0
    private var outputURL: URL?
    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var startedAt = Date()
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var busy = false
    private var overlay: RecordingOverlay?
    private var cursorSamples: [CursorTrack.Sample] = []
    private var clickSamples: [CursorTrack.Click] = []
    private var clickMonitor: Any?
    private var cursorTimer: Timer?
    private var captureRegion: CGRect = .zero
    private var captureScreen: NSScreen?
    /// "Record now" of the Combine dialog: the recording it starts goes back to the dialog, not to the editor.
    private var combine = CombineCapture() { didSet { combineActive = combine.isActive } }
    private var combineCompletion: ((URL?) -> Void)?
    @Published private(set) var combineActive = false

    /// True when "Record now" can start: nothing is recording, counting down or already requested.
    var canRecordForCombine: Bool { !isRecording && !busy && !Countdown.isRunning && !combine.isActive }

    /// Records a video for the Combine dialog: same selector, count-down and menu bar button as a normal recording,
    /// but the file is handed to `completion` instead of opening the editor. `completion(nil)` means cancelled,
    /// refused or no file. Returns false (and never calls `completion`) when a request or recording is in progress.
    @discardableResult
    func recordForCombine(completion: @escaping (URL?) -> Void) -> Bool {
        guard combine.request(recorderBusy: isRecording || busy || Countdown.isRunning) else { return false }
        combineCompletion = completion
        Task {
            await begin(forCombine: true)
            // Still waiting: the selection was cancelled or the start failed, nothing is recording.
            if combine.cancelBeforeRecording() { finishCombine(nil) }
        }
        return true
    }

    private func finishCombine(_ url: URL?) {
        let done = combineCompletion
        combineCompletion = nil
        done?(url)
    }

    /// Same shortcut starts and stops.
    func toggle() {
        if Countdown.isRunning { Countdown.cancel(); return } // the shortcut again cancels a running count-down
        guard !busy else { return }
        if isRecording { Task { await stop() } } else { Task { await begin() } }
    }

    // MARK: Start

    /// Debug: records a fixed region without the selection overlay (MELIES_RECORD_TEST).
    func beginFixed(region: CGRect, screen: NSScreen) async { await begin(fixed: (region, screen)) }

    func stopNow() async { await stop() }

    private func begin(fixed: (rect: CGRect, screen: NSScreen)? = nil, forCombine: Bool = false) async {
        busy = true
        defer { busy = false }

        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            alert(L("rec.perm.title"), L("rec.perm.text"), openSettings: true)
            return
        }
        let chosen: (rect: CGRect, screen: NSScreen)?
        if let fixed { chosen = fixed } else { chosen = await RegionSelector.select() }
        guard let selection = chosen else { return }
        overlay = RecordingOverlay(screen: selection.screen, region: selection.rect)
        // Optional count-down (Settings, off by default): the area stays dimmed and the number shows inside it.
        let countdown = UserDefaults.standard.integer(forKey: Pref.recordCountdown)
        if countdown > 0, fixed == nil {
            guard await Countdown.run(seconds: countdown, region: selection.rect, screen: selection.screen) else {
                closeOverlay()
                return
            }
        }
        try? await Task.sleep(for: .milliseconds(220)) // let the selector disappear before capturing

        do {
            try await startCapture(selection: selection, audio: nil)
            if forCombine, let id = currentRecordingID { combine.recordingStarted(id: id, fromRequest: true) }
        } catch {
            closeOverlay()
            if let failure = error as? RecorderError, case .noDisplay = failure { alert(L("rec.nodisplay"), "") } else { alert(L("rec.failed"), error.localizedDescription) }
        }
    }

    /// Starts the capture of `selection` (rect relative to its screen, top-left origin). `audio` nil follows the
    /// Settings; a value (AI request) overrides them for this recording only.
    private func startCapture(selection: (rect: CGRect, screen: NSScreen), audio: RecordingAudio?) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let id = selection.screen.deviceDescription[key] as? CGDirectDisplayID
        guard let display = content.displays.first(where: { $0.displayID == id }) ?? content.displays.first else { throw RecorderError.noDisplay }

        let scale = selection.screen.backingScaleFactor
        let config = SCStreamConfiguration()
        config.sourceRect = selection.rect
        config.width = even(selection.rect.width * scale)
        config.height = even(selection.rect.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = true

        // Audio: the system sound and/or the microphone, both written into the same movie.
        let defaults = UserDefaults.standard
        let wantsSystem = audio.map { $0 == .system || $0 == .both } ?? defaults.bool(forKey: Pref.recordSystemAudio)
        let wantsMic = audio.map { $0 == .microphone || $0 == .both } ?? defaults.bool(forKey: Pref.recordMicrophone)
        config.capturesAudio = wantsSystem
        config.excludesCurrentProcessAudio = true
        if wantsMic {
            if await Self.microphoneAllowed() {
                config.captureMicrophone = true
            } else if audio != nil {
                throw RecorderError.microphone
            } else {
                Toast.show(L("rec.mic.denied")) // recording goes on without the voice
            }
        }

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
        // The clock starts right before the capture does: taking it after the await would shift the cursor and
        // click times early by the start latency.
        let clockStart = Date()
        try await stream.startCapture()

        self.stream = stream
        self.recordingOutput = output
        self.outputURL = url
        startedAt = clockStart
        elapsed = 0
        isRecording = true
        currentRecordingID = UUID()
        showStatusItem()
        startCursorSampling(region: selection.rect, screen: selection.screen)
    }

    enum RecorderError: LocalizedError {
        case permission, noDisplay, microphone, busy, countdownCancelled
        var errorDescription: String? {
            switch self {
            case .permission: return "Screen recording is not allowed for Méliès. The user must enable it in System Settings > Privacy & Security > Screen Recording."
            case .noDisplay: return "The display is not available."
            case .microphone: return "Microphone access was refused by the user."
            case .busy: return "Méliès is busy with another recording."
            case .countdownCancelled: return "The count-down was cancelled."
            }
        }
    }

    /// Starts a recording asked by an AI client (already validated and approved by the user): no selector.
    @discardableResult
    func startForAI(displayID: Int, rect: CGRect, audio: RecordingAudio, countdown: Int) async throws -> UUID {
        guard !busy, !isRecording, !Countdown.isRunning else { throw RecorderError.busy }
        busy = true
        defer { busy = false }
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw RecorderError.permission
        }
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[key] as? CGDirectDisplayID).map(Int.init) == displayID }) else { throw RecorderError.noDisplay }
        overlay = RecordingOverlay(screen: screen, region: rect)
        if countdown > 0 {
            guard await Countdown.run(seconds: countdown, region: rect, screen: screen) else {
                closeOverlay()
                throw RecorderError.countdownCancelled
            }
        }
        try? await Task.sleep(for: .milliseconds(220))
        do { try await startCapture(selection: (rect, screen), audio: audio) } catch {
            closeOverlay()
            throw error
        }
        guard let id = currentRecordingID else { throw RecorderError.busy }
        return id
    }

    /// Stops and reports the file. The editor opens on it like after any recording.
    func stopForAI(recordingID: UUID) async throws -> RecordingOutcome {
        guard isRecording, currentRecordingID == recordingID else { throw ToolError("That recording is no longer running.") }
        guard let outcome = await stop() else { throw ToolError("The recording produced no file.") }
        return outcome
    }

    /// The last recording that ended (any way), for an AI client that asks afterwards.
    private(set) var lastOutcome: RecordingOutcome?

    // MARK: Stop

    @discardableResult
    private func stop() async -> RecordingOutcome? {
        guard let stream, isRecording else { return nil }
        let recordingID = currentRecordingID
        stopCursorSampling()
        closeOverlay()
        busy = true
        defer { busy = false }

        finishToken += 1
        let token = finishToken
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            finishContinuation = continuation
            Task { try? await stream.stopCapture() }
            // Safety net so a missing delegate callback can never hang the app. It is cancelled as soon as the
            // recording finishes, so it cannot cut short the NEXT stop 6 seconds later.
            safetyTask = Task {
                try? await Task.sleep(for: .seconds(6))
                if !Task.isCancelled { self.resumeFinish(token: token) }
            }
        }

        self.stream = nil
        self.recordingOutput = nil
        isRecording = false
        currentRecordingID = nil
        hideStatusItem()
        var outcome: RecordingOutcome?
        if let url = outputURL, FileManager.default.fileExists(atPath: url.path) {
            var seconds = Date().timeIntervalSince(startedAt)
            if let real = try? await AVURLAsset(url: url).load(.duration).seconds, real.isFinite, real > 0 { seconds = real }
            outcome = RecordingOutcome(path: url.path, duration: seconds, hasClicks: !clickSamples.isEmpty, recordingID: recordingID)
            // Decided before the editor: a recording asked by the Combine dialog goes back to it.
            if case .delivered = combine.recordingFinished(id: recordingID, url: url) {
                finishCombine(url)
            } else if UserDefaults.standard.object(forKey: Pref.openEditorAfterRecording) as? Bool ?? true {
                EditorWindowController.shared.open(url)
            } else {
                Toast.show(L("toast.recorded"))
            }
        }
        if outcome == nil, case .failed = combine.recordingFinished(id: recordingID, url: nil) { finishCombine(nil) }
        // Always replaced, even without a file, so a stale outcome is never read as this recording's.
        lastOutcome = outcome
        return outcome
    }

    private var safetyTask: Task<Void, Never>?

    private func resumeFinish(token: Int? = nil) {
        if let token, token != finishToken { return }
        safetyTask?.cancel()
        safetyTask = nil
        finishContinuation?.resume()
        finishContinuation = nil
    }

    // MARK: Delegates

    nonisolated func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        Task { @MainActor in if self.recordingOutput === recordingOutput { self.resumeFinish() } }
    }

    nonisolated func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        Task { @MainActor in if self.recordingOutput === recordingOutput { self.resumeFinish() } }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            guard self.stream === stream else { return }
            if self.finishContinuation != nil {
                self.resumeFinish()
            } else if self.isRecording {
                // The stream died by itself (display sleep or unplugged): run the normal stop path so the file is
                // kept, the timers stop and the state resets.
                await self.stop()
            }
        }
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

    /// Asks for microphone access the first time; false if the user said no.
    private static func microphoneAllowed() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    // MARK: Cursor track (lets the editor center a zoom on the mouse)

    private func startCursorSampling(region: CGRect, screen: NSScreen) {
        cursorSamples = []
        clickSamples = []
        captureRegion = region
        captureScreen = screen
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleCursor() }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard let self, let m = self.mouseInRegion() else { return }
                self.clickSamples.append(CursorTrack.Click(t: Date().timeIntervalSince(self.startedAt), x: m.x, y: m.y))
            }
        }
    }

    /// Normalized position of the mouse in the recorded region, nil when it is outside.
    private func mouseInRegion() -> (x: Double, y: Double)? {
        guard let screen = captureScreen, captureRegion.width > 0 else { return nil }
        let p = NSEvent.mouseLocation // bottom-left origin, global
        let x = (p.x - screen.frame.minX - captureRegion.minX) / captureRegion.width
        let y = (screen.frame.maxY - p.y - captureRegion.minY) / captureRegion.height
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return (x, y)
    }

    private func sampleCursor() {
        guard let screen = captureScreen, captureRegion.width > 0 else { return }
        let p = NSEvent.mouseLocation // bottom-left origin, global
        let x = (p.x - screen.frame.minX - captureRegion.minX) / captureRegion.width
        let y = (screen.frame.maxY - p.y - captureRegion.minY) / captureRegion.height
        cursorSamples.append(CursorTrack.Sample(t: Date().timeIntervalSince(startedAt), x: min(max(x, 0), 1), y: min(max(y, 0), 1)))
    }

    private func stopCursorSampling() {
        cursorTimer?.invalidate()
        cursorTimer = nil
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
        if !cursorSamples.isEmpty || !clickSamples.isEmpty, let url = outputURL {
            CursorTrack(samples: cursorSamples, clicks: clickSamples).save(for: url)
        }
    }

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

    private func alert(_ title: String, _ text: String, openSettings: Bool = false) {
#if DEBUG || MELIES_HOOKS
        if ProcessInfo.processInfo.environment["MELIES_RECORD_TEST"] != nil { print("[record] alert: \(title) | \(text)"); return }
#endif
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        if openSettings { a.addButton(withTitle: L("rec.perm.open")); a.addButton(withTitle: L("error.close")) }
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn, openSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url) // straight to the switch, not a dead-end message
        }
    }
}
