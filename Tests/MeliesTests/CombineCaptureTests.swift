import XCTest
@testable import Melies

final class CombineCaptureTests: XCTestCase {
    private let file = URL(fileURLWithPath: "/tmp/video2.mov")

    func testRequestIsRefusedWhenARecordingIsInProgress() {
        var c = CombineCapture()
        XCTAssertFalse(c.request(recorderBusy: true))
        XCTAssertEqual(c.phase, .idle)
    }

    func testDoubleRequestIsRefused() {
        var c = CombineCapture()
        XCTAssertTrue(c.request(recorderBusy: false))
        XCTAssertFalse(c.request(recorderBusy: false))
        XCTAssertTrue(c.recordingStarted(id: UUID(), fromRequest: true))
        XCTAssertFalse(c.request(recorderBusy: false), "still refused while its recording runs")
    }

    func testOnlyTheRecordingStartedByTheRequestIsDelivered() {
        var c = CombineCapture()
        XCTAssertTrue(c.request(recorderBusy: false))
        let mine = UUID()
        XCTAssertTrue(c.recordingStarted(id: mine, fromRequest: true))
        XCTAssertEqual(c.recordingFinished(id: UUID(), url: file), .notOurs, "another recording (AI or manual)")
        XCTAssertEqual(c.recordingFinished(id: nil, url: file), .notOurs)
        XCTAssertEqual(c.phase, .recording(mine))
        XCTAssertEqual(c.recordingFinished(id: mine, url: file), .delivered(file))
        XCTAssertEqual(c.phase, .idle)
    }

    func testARecordingNotStartedByTheRequestIsNeverAdopted() {
        var c = CombineCapture()
        XCTAssertTrue(c.request(recorderBusy: false))
        XCTAssertFalse(c.recordingStarted(id: UUID(), fromRequest: false), "AI path")
        XCTAssertEqual(c.phase, .waiting)
        var idle = CombineCapture()
        XCTAssertFalse(idle.recordingStarted(id: UUID(), fromRequest: true), "no request pending")
        XCTAssertEqual(idle.recordingFinished(id: UUID(), url: file), .notOurs)
    }

    func testCancelBeforeRecordingRestores() {
        var c = CombineCapture()
        XCTAssertFalse(c.cancelBeforeRecording(), "nothing to cancel")
        XCTAssertTrue(c.request(recorderBusy: false))
        XCTAssertTrue(c.cancelBeforeRecording())
        XCTAssertEqual(c.phase, .idle)
        XCTAssertTrue(c.request(recorderBusy: false), "a new request works after a cancel")
    }

    func testCancelDoesNotAbortARunningRecording() {
        var c = CombineCapture()
        _ = c.request(recorderBusy: false)
        let id = UUID()
        _ = c.recordingStarted(id: id, fromRequest: true)
        XCTAssertFalse(c.cancelBeforeRecording())
        XCTAssertEqual(c.recordingFinished(id: id, url: file), .delivered(file))
    }

    func testRecordingWithoutFileFails() {
        var c = CombineCapture()
        _ = c.request(recorderBusy: false)
        let id = UUID()
        _ = c.recordingStarted(id: id, fromRequest: true)
        XCTAssertEqual(c.recordingFinished(id: id, url: nil), .failed)
        XCTAssertFalse(c.isActive)
    }
}
