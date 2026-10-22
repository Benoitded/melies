import XCTest
@testable import Melies

final class CursorTrackTests: XCTestCase {
    private typealias S = CursorTrack.Sample
    private typealias C = CursorTrack.Click

    private func track(_ s: [S], clicks: [C] = []) -> CursorTrack { CursorTrack(samples: s, clicks: clicks) }

    /// A fake video path in a fresh folder; the sidecar next to it is written by the test.
    private func videoURL() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("melies-cursor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        return folder.appendingPathComponent("clip.mov")
    }

    private func writeSidecar(_ text: String, for video: URL) throws {
        try Data(text.utf8).write(to: CursorTrack.sidecarURL(for: video))
    }

    // MARK: position(at:)

    func testNoSamplesGivesNoPosition() {
        XCTAssertNil(track([]).position(at: 1))
    }

    func testASingleSampleIsAlwaysTheAnswer() {
        let t = track([S(t: 2, x: 0.3, y: 0.7)])
        XCTAssertEqual(t.position(at: 0), CGPoint(x: 0.3, y: 0.7))
        XCTAssertEqual(t.position(at: 2), CGPoint(x: 0.3, y: 0.7))
        XCTAssertEqual(t.position(at: 99), CGPoint(x: 0.3, y: 0.7))
    }

    func testPositionIsClampedBeforeAndAfterTheSamples() {
        let t = track([S(t: 1, x: 0.1, y: 0.2), S(t: 3, x: 0.9, y: 0.8)])
        XCTAssertEqual(t.position(at: -5), CGPoint(x: 0.1, y: 0.2))
        XCTAssertEqual(t.position(at: 1), CGPoint(x: 0.1, y: 0.2))
        XCTAssertEqual(t.position(at: 3), CGPoint(x: 0.9, y: 0.8))
        XCTAssertEqual(t.position(at: 1000), CGPoint(x: 0.9, y: 0.8))
    }

    func testPositionIsLinearBetweenTwoSamples() throws {
        let t = track([S(t: 1, x: 0.1, y: 0.2), S(t: 3, x: 0.9, y: 0.6)])
        let p = try XCTUnwrap(t.position(at: 2))
        XCTAssertEqual(p.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(p.y, 0.4, accuracy: 1e-9)
        let q = try XCTUnwrap(t.position(at: 1.5))
        XCTAssertEqual(q.x, 0.3, accuracy: 1e-9)
        XCTAssertEqual(q.y, 0.3, accuracy: 1e-9)
    }

    func testPositionPicksTheRightSegmentAmongMany() throws {
        let samples = (0...100).map { S(t: Double($0) / 10, x: Double($0) / 100, y: 1 - Double($0) / 100) } // t in 0...10
        let t = track(samples)
        for probe in stride(from: 0.0, through: 10, by: 0.137) {
            let p = try XCTUnwrap(t.position(at: probe))
            XCTAssertEqual(p.x, probe / 10, accuracy: 1e-9, "t=\(probe)")
            XCTAssertEqual(p.y, 1 - probe / 10, accuracy: 1e-9, "t=\(probe)")
        }
    }

    func testTwoSamplesAtTheSameTimeDoNotDivideByZero() throws {
        let t = track([S(t: 0, x: 0, y: 0), S(t: 1, x: 0.2, y: 0.2), S(t: 1, x: 0.8, y: 0.8), S(t: 2, x: 1, y: 1)])
        for probe in [0.5, 0.999, 1.0, 1.001, 1.5] {
            let p = try XCTUnwrap(t.position(at: probe))
            XCTAssertTrue(p.x.isFinite && p.y.isFinite, "t=\(probe)")
            XCTAssertTrue((0...1).contains(p.x) && (0...1).contains(p.y), "t=\(probe)")
        }
    }

    // MARK: load / save

    func testTheSidecarSitsNextToTheVideo() {
        XCTAssertEqual(CursorTrack.sidecarURL(for: URL(fileURLWithPath: "/a/b/clip.mov")).path, "/a/b/clip.cursor.json")
    }

    func testSaveThenLoadRoundTripsWithRounding() throws {
        let video = try videoURL()
        track([S(t: 0.12345, x: 0.123456, y: 0.987654), S(t: 1, x: 0.5, y: 0.5)], clicks: [C(t: 0.5, x: 0.25, y: 0.75)]).save(for: video)
        let loaded = try XCTUnwrap(CursorTrack.load(for: video))
        XCTAssertEqual(loaded.samples.count, 2)
        XCTAssertEqual(loaded.samples[0].t, 0.123, accuracy: 1e-9, "times keep 3 decimals")
        XCTAssertEqual(loaded.samples[0].x, 0.1235, accuracy: 1e-9, "positions keep 4 decimals")
        XCTAssertEqual(loaded.samples[0].y, 0.9877, accuracy: 1e-9)
        XCTAssertEqual(loaded.clicks.count, 1)
        XCTAssertEqual(loaded.clicks[0].x, 0.25, accuracy: 1e-9)
    }

    func testNoSidecarMeansNoTrack() throws {
        XCTAssertNil(CursorTrack.load(for: try videoURL()))
    }

    func testAnEmptyFileIsRefused() throws {
        let video = try videoURL()
        try writeSidecar("", for: video)
        XCTAssertNil(CursorTrack.load(for: video))
    }

    func testMalformedJSONIsRefused() throws {
        for text in ["{not json", "[", "null", "42", "\"cursor\"", "{\"cursor\": 3}", "[[0, 0.1, 0.2], [1, 0.3", "\u{0}\u{1}\u{2}", "{}", "[{}]"] {
            let video = try videoURL()
            try writeSidecar(text, for: video)
            XCTAssertNil(CursorTrack.load(for: video), text)
        }
    }

    func testTheLegacyPlainArrayStillLoads() throws {
        let video = try videoURL()
        try writeSidecar("[[0,0.1,0.2],[1,0.3,0.4]]", for: video)
        let t = try XCTUnwrap(CursorTrack.load(for: video))
        XCTAssertEqual(t.samples.count, 2)
        XCTAssertTrue(t.clicks.isEmpty)
        XCTAssertEqual(t.samples[1].x, 0.3)
    }

    func testThePayloadFormatLoadsCursorAndClicks() throws {
        let video = try videoURL()
        try writeSidecar(#"{"cursor":[[0,0.1,0.2]],"clicks":[[0.5,0.6,0.7],[1.5,0.2,0.3]]}"#, for: video)
        let t = try XCTUnwrap(CursorTrack.load(for: video))
        XCTAssertEqual(t.samples.count, 1)
        XCTAssertEqual(t.clicks.count, 2)
        XCTAssertEqual(t.clicks[1].t, 1.5)
    }

    func testClicksWithoutCursorSamplesStillLoad() throws {
        let video = try videoURL()
        try writeSidecar(#"{"cursor":[],"clicks":[[0.5,0.6,0.7]]}"#, for: video)
        let t = try XCTUnwrap(CursorTrack.load(for: video))
        XCTAssertTrue(t.samples.isEmpty)
        XCTAssertEqual(t.clicks.count, 1)
        XCTAssertNil(t.position(at: 0.5))
    }

    func testAPayloadWithNothingInItIsRefused() throws {
        let video = try videoURL()
        try writeSidecar(#"{"cursor":[],"clicks":[]}"#, for: video)
        XCTAssertNil(CursorTrack.load(for: video))
        try writeSidecar("[]", for: video)
        XCTAssertNil(CursorTrack.load(for: video))
    }

    func testValuesAreClampedToTheFrame() throws {
        let video = try videoURL()
        try writeSidecar(#"{"cursor":[[0,-3,7],[1,0.5,0.5]],"clicks":[[0,9,-9]]}"#, for: video)
        let t = try XCTUnwrap(CursorTrack.load(for: video))
        XCTAssertEqual(t.samples[0].x, 0)
        XCTAssertEqual(t.samples[0].y, 1)
        XCTAssertEqual(t.clicks[0].x, 1)
        XCTAssertEqual(t.clicks[0].y, 0)
    }

    func testRowsWithTheWrongShapeOrNonFiniteValuesAreDropped() throws {
        let video = try videoURL()
        try writeSidecar("[[0,0.1],[1,0.2,0.3,0.4],[2,0.5,0.5],[]]", for: video)
        let t = try XCTUnwrap(CursorTrack.load(for: video))
        XCTAssertEqual(t.samples.map(\.t), [2])
        // JSON has no NaN, but a huge exponent overflows to infinity when parsed.
        try writeSidecar("[[0,1e999,0.2],[1,0.2,0.3]]", for: video)
        let u = CursorTrack.load(for: video)
        XCTAssertTrue(u == nil || u!.samples.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) })
    }

    func testAnOversizedSidecarIsRefusedUnread() throws {
        let video = try videoURL()
        let valid = "[[0,0.1,0.2]]"
        try writeSidecar(valid + String(repeating: " ", count: 5_000_001), for: video)
        XCTAssertNil(CursorTrack.load(for: video))
    }

    func testTheNumberOfRowsIsBounded() throws {
        let video = try videoURL()
        let rows = (0..<5_100).map { "[\($0),0.5,0.5]" }.joined(separator: ",")
        try writeSidecar(#"{"cursor":[[0,0.1,0.1]],"clicks":["# + rows + "]}", for: video)
        XCTAssertEqual(try XCTUnwrap(CursorTrack.load(for: video)).clicks.count, 5_000)
    }

    // MARK: ClickSet

    func testAClickIsActiveForItsAnimationWindowOnly() {
        let set = ClickSet(clicks: [C(t: 2, x: 0.5, y: 0.5)], color: .yellow, size: 36)
        XCTAssertFalse(set.isActive(at: 1.999))
        XCTAssertTrue(set.isActive(at: 2))
        XCTAssertTrue(set.isActive(at: 2.3))
        XCTAssertTrue(set.isActive(at: 2 + ClickSet.duration))
        XCTAssertFalse(set.isActive(at: 2 + ClickSet.duration + 0.001))
    }

    func testSeveralClicksAndNoClicks() {
        let set = ClickSet(clicks: [C(t: 1, x: 0, y: 0), C(t: 10, x: 1, y: 1), C(t: 5, x: 0.5, y: 0.5)], color: .red, size: 20)
        XCTAssertTrue(set.isActive(at: 1.2))
        XCTAssertFalse(set.isActive(at: 3))
        XCTAssertTrue(set.isActive(at: 5.5), "clicks need not be sorted")
        XCTAssertTrue(set.isActive(at: 10.4))
        XCTAssertFalse(ClickSet(clicks: [], color: .red, size: 20).isActive(at: 0))
    }

    func testNoClickSetWithoutRecordedClicks() {
        XCTAssertNil(ClickSet.current(for: nil))
        XCTAssertNil(ClickSet.current(for: track([S(t: 0, x: 0, y: 0)])))
        let set = ClickSet.current(for: track([], clicks: [C(t: 1, x: 0.1, y: 0.1)]))
        XCTAssertEqual(set?.clicks.count, 1)
        XCTAssertGreaterThan(set?.size ?? 0, 0)
    }
}
