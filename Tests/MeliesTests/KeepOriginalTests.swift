import XCTest
@testable import Melies

@MainActor
final class KeepOriginalTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("melies-keep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDown() { try? FileManager.default.removeItem(at: folder) }

    private func make(_ name: String, bytes: Int) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        return url
    }

    func testTheOriginalAndItsCursorFileGoToTheTrashOnceTheCopyIsThere() throws {
        let original = try make("a.mov", bytes: 100)
        let sidecar = try make("a.cursor.json", bytes: 10)
        let saved = try make("a-optimized.mp4", bytes: 50)
        var trashed: [String] = []
        XCTAssertTrue(EditorModel.trashOriginal(original, keeping: saved) { trashed.append($0.lastPathComponent) })
        XCTAssertEqual(trashed, [original.lastPathComponent, sidecar.lastPathComponent])
    }

    func testNothingIsTrashedWhenTheSavedCopyIsMissingOrEmpty() throws {
        let original = try make("b.mov", bytes: 100)
        var trashed: [String] = []
        XCTAssertFalse(EditorModel.trashOriginal(original, keeping: folder.appendingPathComponent("missing.mp4")) { trashed.append($0.lastPathComponent) })
        let empty = try make("b-optimized.mp4", bytes: 0)
        XCTAssertFalse(EditorModel.trashOriginal(original, keeping: empty) { trashed.append($0.lastPathComponent) })
        XCTAssertTrue(trashed.isEmpty)
    }

    func testTheOriginalIsNeverTrashedWhenItIsTheSavedFile() throws {
        let original = try make("c.mov", bytes: 100)
        var trashed: [String] = []
        XCTAssertFalse(EditorModel.trashOriginal(original, keeping: original) { trashed.append($0.lastPathComponent) })
        XCTAssertTrue(trashed.isEmpty)
    }

    func testAFailedTrashLeavesTheStatusToTheCaller() throws {
        let original = try make("d.mov", bytes: 100)
        let saved = try make("d-optimized.mp4", bytes: 50)
        struct Boom: Error {}
        XCTAssertFalse(EditorModel.trashOriginal(original, keeping: saved) { _ in throw Boom() })
    }
}
