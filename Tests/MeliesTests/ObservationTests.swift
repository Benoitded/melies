import Observation
import XCTest
@testable import Melies

@MainActor
final class ObservationTests: XCTestCase {
    private func makeModel() -> EditorModel {
        EditorModel(url: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("melies-missing.mov"))
    }

    /// Runs `read` under observation, then `change`; returns whether the read was invalidated.
    private func invalidated(read: () -> Void, change: () -> Void) -> Bool {
        var fired = false
        withObservationTracking { read() } onChange: { fired = true }
        change()
        return fired
    }

    func testPlayheadDoesNotInvalidateViewsThatDoNotReadIt() {
        let model = makeModel()
        XCTAssertFalse(invalidated(read: { _ = model.duration; _ = model.start; _ = model.canUndo }, change: { model.current = 3 }))
    }

    func testPlayheadInvalidatesViewsThatReadIt() {
        let model = makeModel()
        XCTAssertTrue(invalidated(read: { _ = model.current }, change: { model.current = 3 }))
    }

    func testDidSetStillFeedsUndoAndIsTracked() {
        let model = makeModel()
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(invalidated(read: { _ = model.canUndo }, change: { model.start = 1 }))
        XCTAssertTrue(model.canUndo)
        XCTAssertFalse(model.canRedo)
        model.undo()
        XCTAssertEqual(model.start, 0)
        XCTAssertTrue(model.canRedo)
    }

    func testEditRevisionIsTracked() {
        let model = makeModel()
        XCTAssertTrue(invalidated(read: { _ = model.editRevision }, change: { model.includeAudio = false }))
    }

    func testIgnoredStateDoesNotInvalidate() {
        let model = makeModel()
        XCTAssertFalse(invalidated(read: { _ = model.canvasSize }, change: { model.canvasSize = CGSize(width: 10, height: 10) }))
    }
}
