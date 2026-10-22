import Foundation

/// Pure state machine of "record video 2 right now" from the Combine dialog. No AppKit, no capture: the recorder
/// feeds it events, so the rules are unit tested without any permission.
///
/// Rules: one request at a time; only the recording started by the request is delivered (a recording started by the
/// AI or by an unrelated shortcut is never captured); a cancel before the recording starts restores the dialog.
struct CombineCapture: Equatable {
    enum Phase: Equatable {
        case idle
        /// Asked, the region selector / countdown is running, no recording yet.
        case waiting
        /// The recording started by the request is running.
        case recording(UUID)
    }

    enum Finish: Equatable {
        /// Not the recording of the request: the normal flow (editor) applies.
        case notOurs
        /// The request's recording ended with this file: hand it to the dialog, do not open the editor.
        case delivered(URL)
        /// The request's recording ended without a file.
        case failed
    }

    private(set) var phase: Phase = .idle

    var isActive: Bool { phase != .idle }

    /// Refused (false) when another request is active or something is already recording.
    mutating func request(recorderBusy: Bool) -> Bool {
        guard phase == .idle, !recorderBusy else { return false }
        phase = .waiting
        return true
    }

    /// A recording started. Adopted only when it comes from the request's own flow (`fromRequest`).
    @discardableResult
    mutating func recordingStarted(id: UUID, fromRequest: Bool) -> Bool {
        guard fromRequest, phase == .waiting else { return false }
        phase = .recording(id)
        return true
    }

    /// The request ended before any recording started (Esc, countdown cancelled, permission, error).
    /// Returns true when there was a pending request to cancel (the dialog must come back).
    mutating func cancelBeforeRecording() -> Bool {
        guard phase == .waiting else { return false }
        phase = .idle
        return true
    }

    /// A recording ended (any way) with or without a file.
    mutating func recordingFinished(id: UUID?, url: URL?) -> Finish {
        guard case .recording(let mine) = phase, id == mine else { return .notOurs }
        phase = .idle
        if let url { return .delivered(url) }
        return .failed
    }
}
