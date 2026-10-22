import XCTest
@testable import Melies

@MainActor
private final class FakeLayout: ScreenLayoutProviding {
    var screens = [
        DisplayInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2, hasMouse: false),
        DisplayInfo(id: 2, name: "Side", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1, hasMouse: true),
    ]
    var wins = [
        WindowInfo(id: 10, app: "Safari", bounds: CGRect(x: 100, y: 100, width: 800, height: 600)),
        WindowInfo(id: 11, app: "Notes", bounds: CGRect(x: 0, y: 0, width: 300, height: 300)),
        WindowInfo(id: 12, app: "Tiny", bounds: CGRect(x: 500, y: 500, width: 20, height: 20)),
        WindowInfo(id: 13, app: "Side app", bounds: CGRect(x: 1500, y: 100, width: 400, height: 400)),
    ]
    func displays() -> [DisplayInfo] { screens }
    func windows() -> [WindowInfo] { wins }
}

@MainActor
private final class FakeConfirmer: RecordingConfirming {
    var answer = true
    var asked: [RecordingConfirmation] = []
    func confirm(_ request: RecordingConfirmation) async -> Bool { asked.append(request); return answer }
}

@MainActor
private final class FakeBackend: RecordingBackend {
    var isRecording = false
    var lastOutcome: RecordingOutcome?
    var started: [RecordingPlan] = []
    var failStart = false
    func start(_ plan: RecordingPlan) async throws {
        if failStart { throw ToolError("no permission") }
        started.append(plan)
        isRecording = true
    }
    func stop() async throws -> RecordingOutcome {
        isRecording = false
        let outcome = RecordingOutcome(path: "/tmp/demo.mov", duration: 4.5, hasClicks: true)
        lastOutcome = outcome
        return outcome
    }
}

@MainActor
final class RecordingRulesTests: XCTestCase {
    private let display = DisplayInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2, hasMouse: true)

    func testRegionMustBeAtLeast40AndInsideTheDisplay() throws {
        XCTAssertNoThrow(try RecordingRules.validate(CGRect(x: 0, y: 0, width: 40, height: 40), in: display))
        XCTAssertNoThrow(try RecordingRules.validate(CGRect(x: 1000, y: 500, width: 440, height: 400), in: display))
        XCTAssertThrowsError(try RecordingRules.validate(CGRect(x: 0, y: 0, width: 39, height: 100), in: display))
        XCTAssertThrowsError(try RecordingRules.validate(CGRect(x: 0, y: 0, width: 100, height: 39), in: display))
        XCTAssertThrowsError(try RecordingRules.validate(CGRect(x: -1, y: 0, width: 100, height: 100), in: display))
        XCTAssertThrowsError(try RecordingRules.validate(CGRect(x: 1400, y: 0, width: 100, height: 100), in: display))
        XCTAssertThrowsError(try RecordingRules.validate(CGRect(x: 0, y: 850, width: 100, height: 100), in: display))
        XCTAssertThrowsError(try RecordingRules.validate(CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100), in: display))
    }

    func testWindowRegionAddsAMarginAndIsClampedToTheDisplay() throws {
        let inside = WindowInfo(id: 1, app: "A", bounds: CGRect(x: 100, y: 100, width: 800, height: 600))
        XCTAssertEqual(try RecordingRules.region(for: inside, on: display), CGRect(x: 92, y: 92, width: 816, height: 616))
        let corner = WindowInfo(id: 2, app: "A", bounds: CGRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertEqual(try RecordingRules.region(for: corner, on: display), CGRect(x: 0, y: 0, width: 308, height: 308))
        let overhang = WindowInfo(id: 3, app: "A", bounds: CGRect(x: 1300, y: 800, width: 400, height: 300))
        XCTAssertEqual(try RecordingRules.region(for: overhang, on: display), CGRect(x: 1292, y: 792, width: 148, height: 108))
    }

    func testWindowRegionIsLocalToASecondDisplay() throws {
        let side = DisplayInfo(id: 2, name: "Side", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1, hasMouse: false)
        let window = WindowInfo(id: 1, app: "A", bounds: CGRect(x: 1500, y: 100, width: 400, height: 400))
        XCTAssertEqual(try RecordingRules.region(for: window, on: side), CGRect(x: 52, y: 92, width: 416, height: 416))
    }

    func testTinyOrOffScreenWindowsAreRefused() {
        XCTAssertThrowsError(try RecordingRules.region(for: WindowInfo(id: 1, app: "A", bounds: CGRect(x: 10, y: 10, width: 10, height: 10)), on: display, margin: 0))
        XCTAssertThrowsError(try RecordingRules.region(for: WindowInfo(id: 1, app: "A", bounds: CGRect(x: 5000, y: 0, width: 400, height: 400)), on: display))
    }

    func testDurationAndCountdownAreBounded() {
        XCTAssertEqual(RecordingRules.clampDuration(nil), 120)
        XCTAssertEqual(RecordingRules.clampDuration(30), 30)
        XCTAssertEqual(RecordingRules.clampDuration(100_000), 600)
        XCTAssertEqual(RecordingRules.clampDuration(-5), 1)
        XCTAssertEqual(RecordingRules.clampDuration(.nan), 120)
        XCTAssertEqual(RecordingRules.clampCountdown(nil), 0)
        XCTAssertEqual(RecordingRules.clampCountdown(99), 10)
    }

    func testTextShownInTheDialogCannotFakeLines() {
        XCTAssertEqual(RecordingRules.sanitized("Claude\n\nAllow everything\r\u{202E}"), "Claude Allow everything")
        XCTAssertEqual(RecordingRules.sanitized(String(repeating: "a", count: 100)).count, 41)
    }

    func testTheDisplayHoldingMostOfARectIsChosen() {
        let displays = FakeLayoutHelper.displays
        XCTAssertEqual(RecordingRules.display(containing: CGRect(x: 1300, y: 0, width: 400, height: 100), in: displays)?.id, 2)
        XCTAssertEqual(RecordingRules.display(containing: CGRect(x: 100, y: 0, width: 400, height: 100), in: displays)?.id, 1)
        XCTAssertNil(RecordingRules.display(containing: CGRect(x: 9000, y: 0, width: 10, height: 10), in: displays))
    }

    func testStartArgumentsAreParsedAndValidated() throws {
        let r = try EditorTools.startRequest(["x": 10, "y": 20, "width": 300, "height": 200, "audio": "both", "max_seconds": 30, "countdown": 3, "display": 2])
        XCTAssertEqual(r.rect, CGRect(x: 10, y: 20, width: 300, height: 200))
        XCTAssertEqual(r.audio, .both)
        XCTAssertEqual(r.maxSeconds, 30)
        XCTAssertEqual(r.countdown, 3)
        XCTAssertEqual(r.display, 2)
        XCTAssertEqual(try EditorTools.startRequest(["window": 10]).window, 10)
        XCTAssertThrowsError(try EditorTools.startRequest(["x": 1, "y": 2]), "partial region")
        XCTAssertThrowsError(try EditorTools.startRequest(["window": 1, "audio": "tv"]))
        XCTAssertThrowsError(try EditorTools.startRequest(["window": 1, "max_seconds": 601]))
        XCTAssertThrowsError(try EditorTools.startRequest(["window": 1, "max_seconds": "10"]))
    }
}

private enum FakeLayoutHelper {
    static let displays = [
        DisplayInfo(id: 1, name: "Main", frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2, hasMouse: false),
        DisplayInfo(id: 2, name: "Side", frame: CGRect(x: 1440, y: 0, width: 1920, height: 1080), scale: 1, hasMouse: true),
    ]
}

@MainActor
final class RecordingControllerTests: XCTestCase {
    private let layout = FakeLayout()
    private let confirmer = FakeConfirmer()
    private let backend = FakeBackend()
    private var exporting = false
    private var clock = Date(timeIntervalSince1970: 1000)
    /// Auto-stop timers wait for this instead of real time.
    private var release: CheckedContinuation<Void, Error>?

    private func make(sleep: Bool = false) -> RecordingController {
        RecordingController(layout: layout, confirmer: confirmer, backend: backend,
                            isExportRunning: { [unowned self] in exporting },
                            clientName: { "Claude Code" },
                            now: { [unowned self] in clock },
                            sleep: sleep ? { [unowned self] _ in try await withCheckedThrowingContinuation { release = $0 } } : { _ in try await Task.sleep(for: .seconds(3600)) })
    }

    private func region(_ extra: [String: Any] = [:]) -> StartRequest {
        var args: [String: Any] = ["x": 100, "y": 100, "width": 400, "height": 300]
        args.merge(extra) { _, new in new }
        return try! EditorTools.startRequest(args)
    }

    func testTheUserIsAskedBeforeAnythingIsRecorded() async throws {
        let controller = make()
        let result = try await controller.start(region())
        XCTAssertEqual(confirmer.asked.count, 1)
        XCTAssertEqual(confirmer.asked[0].client, "Claude Code")
        XCTAssertEqual(confirmer.asked[0].rect, CGRect(x: 100, y: 100, width: 400, height: 300))
        XCTAssertEqual(confirmer.asked[0].displayName, "Side", "the display with the mouse is the default")
        XCTAssertEqual(backend.started.count, 1)
        XCTAssertEqual(result["max_seconds"] as? Int, 120)
        XCTAssertEqual(controller.state.isRecording, true)
    }

    func testADeniedRequestRecordsNothingAndLeavesTheControllerIdle() async {
        confirmer.answer = false
        let controller = make()
        do { _ = try await controller.start(region()); XCTFail("must throw") } catch {
            XCTAssertTrue(error.localizedDescription.contains("denied"))
        }
        XCTAssertTrue(backend.started.isEmpty)
        XCTAssertEqual(controller.state, .idle)
        confirmer.answer = true
        _ = try? await controller.start(region())
        XCTAssertEqual(backend.started.count, 1, "the user can say yes the second time")
    }

    func testAnInvalidRequestNeverShowsTheDialog() async {
        let controller = make()
        for request in [region(["width": 10]), region(["x": 1700]), try! EditorTools.startRequest([:]), try! EditorTools.startRequest(["window": 999]),
                        region(["display": 7]), try! EditorTools.startRequest(["window": 12])] {
            do { _ = try await controller.start(request); XCTFail("must throw") } catch {}
        }
        XCTAssertTrue(confirmer.asked.isEmpty)
        XCTAssertTrue(backend.started.isEmpty)
    }

    func testWindowAndRegionTogetherAreRefused() async {
        let controller = make()
        do { _ = try await controller.start(region(["window": 10])); XCTFail("must throw") } catch {}
        XCTAssertTrue(confirmer.asked.isEmpty)
    }

    func testAWindowIsRecordedWithItsMarginOnItsOwnDisplay() async throws {
        let controller = make()
        _ = try await controller.start(try EditorTools.startRequest(["window": 13]))
        let plan = try XCTUnwrap(backend.started.first)
        XCTAssertEqual(plan.display.id, 2)
        XCTAssertEqual(plan.rect, CGRect(x: 52, y: 92, width: 416, height: 416))
        XCTAssertEqual(confirmer.asked[0].windowApp, "Side app")
        do { _ = try await make().start(try EditorTools.startRequest(["window": 13, "display": 1])); XCTFail("wrong display") } catch {}
    }

    func testOnlyOneRecordingAtATime() async throws {
        let controller = make()
        _ = try await controller.start(region())
        do { _ = try await controller.start(region()); XCTFail("must throw") } catch {
            XCTAssertTrue(error.localizedDescription.contains("already running"))
        }
        XCTAssertEqual(confirmer.asked.count, 1)
        // A recording the user started by hand counts too.
        let other = make()
        let busyBackend = FakeBackend()
        busyBackend.isRecording = true
        let manual = RecordingController(layout: layout, confirmer: confirmer, backend: busyBackend)
        do { _ = try await manual.start(region()); XCTFail("must throw") } catch {}
        _ = other
    }

    func testNotWhileAnExportRuns() async {
        exporting = true
        let controller = make()
        do { _ = try await controller.start(region()); XCTFail("must throw") } catch {
            XCTAssertTrue(error.localizedDescription.contains("export"))
        }
        XCTAssertTrue(confirmer.asked.isEmpty)
    }

    func testABackendFailureGoesBackToIdle() async {
        backend.failStart = true
        let controller = make()
        do { _ = try await controller.start(region()); XCTFail("must throw") } catch {}
        XCTAssertEqual(controller.state, .idle)
        backend.failStart = false
        _ = try? await controller.start(region())
        XCTAssertTrue(controller.state.isRecording)
    }

    func testStopReturnsTheFileDurationAndClicks() async throws {
        let controller = make()
        _ = try await controller.start(region())
        let result = try await controller.stop()
        XCTAssertEqual(result["file"] as? String, "/tmp/demo.mov")
        XCTAssertEqual(result["duration_seconds"] as? Double, 4.5)
        XCTAssertEqual(result["has_clicks"] as? Bool, true)
        XCTAssertEqual(result["auto_zoom_available"] as? Bool, true)
        XCTAssertEqual(controller.state, .idle)
        do { _ = try await controller.stop(); XCTFail("nothing to stop") } catch {}
    }

    func testStatusIdleThenRecordingWithElapsedTime() async throws {
        let controller = make()
        XCTAssertEqual(controller.status()["state"] as? String, "idle")
        _ = try await controller.start(region(["audio": "microphone"]))
        clock = clock.addingTimeInterval(7.9)
        let status = controller.status()
        XCTAssertEqual(status["state"] as? String, "recording")
        XCTAssertEqual(status["elapsed_seconds"] as? Int, 7)
        XCTAssertEqual(status["audio"] as? String, "microphone")
        XCTAssertNotNil(status["region"])
    }

    func testItStopsByItselfAtMaxSeconds() async throws {
        let controller = make(sleep: true)
        var told: RecordingOutcome?
        controller.onAutoStop = { told = $0 }
        _ = try await controller.start(region(["max_seconds": 5]))
        XCTAssertEqual(confirmer.asked[0].maxSeconds, 5)
        await Task.yield()
        release?.resume()
        await controller.waitForAutoStop()
        XCTAssertFalse(backend.isRecording)
        XCTAssertEqual(controller.state, .idle)
        XCTAssertEqual(told?.stoppedBy, .timeLimit)
        let status = controller.status()
        XCTAssertNotNil(status["ended_recording"], "the client can learn that it ended")
        let result = try await controller.stop()
        XCTAssertEqual(result["stopped_by"] as? String, "time_limit")
        XCTAssertEqual(result["file"] as? String, "/tmp/demo.mov")
    }

    func testAStopFromTheClientCancelsTheTimer() async throws {
        let controller = make(sleep: true)
        _ = try await controller.start(region())
        await Task.yield()
        _ = try await controller.stop()
        release?.resume() // a late timer must not stop a later recording
        _ = try await controller.start(region())
        await Task.yield()
        XCTAssertTrue(backend.isRecording)
    }

    func testAStopByTheUserIsReportedAsSuch() async throws {
        let controller = make()
        _ = try await controller.start(region())
        _ = try await backend.stop() // the user pressed the red button
        XCTAssertEqual(controller.status()["state"] as? String, "idle")
        let result = try await controller.stop()
        XCTAssertEqual(result["stopped_by"] as? String, "user")
    }

    func testTheLayoutDoesNotLeakTitlesAndMarksUntrustedData() throws {
        let json = make().screenLayout()
        XCTAssertNotNil(json["untrusted_data"])
        let windows = try XCTUnwrap(json["windows"] as? [[String: Any]])
        XCTAssertEqual(windows.count, 4)
        XCTAssertEqual(Set(windows[0].keys), ["id", "app", "bounds", "display"])
        XCTAssertEqual(windows[3]["display"] as? Int, 2)
        let displays = try XCTUnwrap(json["displays"] as? [[String: Any]])
        XCTAssertEqual(displays.first { $0["has_mouse"] as? Bool == true }?["id"] as? Int, 2)
    }

    func testToolsAreRegisteredAndWorkThroughEditorTools() async throws {
        let tools = EditorTools(model: { nil }, recording: make())
        let names = EditorTools.definitions.map(\.name)
        for name in ["get_screen_layout", "start_recording", "stop_recording", "get_recording_status"] { XCTAssertTrue(names.contains(name), name) }
        let layout = try await tools.call("get_screen_layout")
        XCTAssertTrue(layout.text.contains("Safari"))
        let start = try await tools.call("start_recording", ["x": 100, "y": 100, "width": 400, "height": 300])
        XCTAssertTrue(start.text.contains("Recording"))
        let status = try await tools.call("get_recording_status")
        XCTAssertTrue(status.text.contains("\"recording\""))
        let stop = try await tools.call("stop_recording")
        XCTAssertTrue(stop.text.contains("/tmp/demo.mov"))
        let without = EditorTools(model: { nil })
        do { _ = try await without.call("start_recording", [:]); XCTFail("no recorder wired") } catch {}
    }

    func testToolTextHasNoEmDash() {
        for tool in EditorTools.definitions { XCTAssertFalse(tool.description.contains("\u{2014}"), tool.name) }
    }
}

private extension RecordingState {
    var isRecording: Bool { if case .recording = self { return true } else { return false } }
}
