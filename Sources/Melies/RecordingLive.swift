import AppKit
import CoreGraphics

// The real implementations of the seams of RecordingControl.swift. Not unit tested: they need a screen, the
// user, and the screen recording permission.

/// Displays from NSScreen, windows from the window server (no titles are read).
@MainActor
struct LiveScreenLayout: ScreenLayoutProviding {
    func displays() -> [DisplayInfo] {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        let mouse = CGEvent(source: nil)?.location ?? .zero // global, top-left origin: same space as CGDisplayBounds
        return NSScreen.screens.compactMap { screen in
            guard let id = screen.deviceDescription[key] as? CGDirectDisplayID else { return nil }
            let frame = CGDisplayBounds(id)
            return DisplayInfo(id: Int(id), name: screen.localizedName, frame: frame, scale: Double(screen.backingScaleFactor), hasMouse: frame.contains(mouse))
        }
    }

    func windows() -> [WindowInfo] {
        let ownPID = Int(ProcessInfo.processInfo.processIdentifier)
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [WindowInfo] = []
        for entry in list {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? Int, pid != ownPID,
                  let app = entry[kCGWindowOwnerName as String] as? String, !app.isEmpty,
                  let id = entry[kCGWindowNumber as String] as? Int,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= RecordingRules.minSide, bounds.height >= RecordingRules.minSide else { continue }
            result.append(WindowInfo(id: id, app: app, bounds: bounds))
            if result.count >= 60 { break }
        }
        return result
    }
}

/// A native alert, Deny by default, no "always allow", denies by itself after 30 seconds.
@MainActor
struct AlertConfirmer: RecordingConfirming {
    func confirm(_ request: RecordingConfirmation) async -> Bool {
        let rect = request.rect
        let line = L("mcprec.region", target(request), Int(rect.width), Int(rect.height), Int(rect.minX), Int(rect.minY))
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L("mcprec.title", request.client)
        alert.informativeText = L("mcprec.text", line, L("mcprec.audio." + request.audio.rawValue), Int(request.maxSeconds))
        let deny = alert.addButton(withTitle: L("mcprec.deny"))
        let allow = alert.addButton(withTitle: L("mcprec.allow"))
        deny.keyEquivalent = "\r" // Return refuses
        allow.keyEquivalent = ""
        // The timer must run while the alert is modal, hence the common modes.
        var timedOut = false
        let timer = Timer(timeInterval: RecordingRules.confirmationTimeout, repeats: false) { _ in
            timedOut = true
            NSApp.abortModal()
        }
        RunLoop.main.add(timer, forMode: .common)
        NSApp.activate(ignoringOtherApps: true)
        let answer = alert.runModal()
        timer.invalidate()
        return !timedOut && answer == .alertSecondButtonReturn
    }

    private func target(_ r: RecordingConfirmation) -> String {
        if let app = r.windowApp { return L("mcprec.target.window", app, r.displayName) }
        return L("mcprec.target.display", r.displayName)
    }
}

/// `ScreenRecorder` behind the `RecordingBackend` seam.
@MainActor
final class LiveRecordingBackend: RecordingBackend {
    private let recorder = ScreenRecorder.shared
    var isRecording: Bool { recorder.isRecording }
    var lastOutcome: RecordingOutcome? { recorder.lastOutcome }

    var currentRecordingID: UUID? { recorder.currentRecordingID }

    func start(_ plan: RecordingPlan) async throws -> UUID {
        try await recorder.startForAI(displayID: plan.display.id, rect: plan.rect, audio: plan.audio, countdown: plan.countdown)
    }

    func stop(recordingID: UUID) async throws -> RecordingOutcome { try await recorder.stopForAI(recordingID: recordingID) }
}
