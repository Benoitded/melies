import XCTest
@testable import Melies

final class AutoZoomTests: XCTestCase {
    private func click(_ t: Double, _ x: Double, _ y: Double) -> CursorTrack.Click { .init(t: t, x: x, y: y) }
    private func zoom(_ strength: AutoZoomStrength = .normal, range: ClosedRange<Double> = 0...20, base: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1)) -> AutoZoom {
        AutoZoom(strength: strength, range: range, base: base)
    }

    func testSingleClickZoomsInBeforeAndOutAfter() {
        let r = zoom().generate(from: [click(5, 0.5, 0.5)])
        XCTAssertEqual(r.zooms, 1)
        XCTAssertEqual(r.points.count, 2)
        XCTAssertEqual(r.points[0].scale, 2.0, accuracy: 0.001)
        XCTAssertEqual(r.points[0].time, 4.5, accuracy: 0.001)   // 0.5 s before the click
        XCTAssertEqual(r.points[1].scale, 1.0, accuracy: 0.001)
        XCTAssertEqual(r.points[1].time, 6.3, accuracy: 0.001)   // 1.3 s after it
    }

    func testStrengthSetsTheLevel() {
        XCTAssertEqual(zoom(.subtle).generate(from: [click(5, 0.5, 0.5)]).points[0].scale, 1.5, accuracy: 0.001)
        XCTAssertEqual(zoom(.strong).generate(from: [click(5, 0.5, 0.5)]).points[0].scale, 2.6, accuracy: 0.001)
    }

    func testCenterNeverShowsOutsideTheFrame() {
        let r = zoom().generate(from: [click(5, 0.02, 0.98)])
        let c = r.points[0].center
        XCTAssertGreaterThanOrEqual(c.x, 0.25 - 0.0001)   // half the view at 2x
        XCTAssertLessThanOrEqual(c.y, 0.75 + 0.0001)
    }

    func testCloseClicksShareOneStillZoom() {
        let r = zoom().generate(from: [click(5, 0.50, 0.50), click(6, 0.55, 0.52)])
        XCTAssertEqual(r.zooms, 1)
        XCTAssertEqual(r.clicks, 2)
        XCTAssertEqual(r.points.count, 2, "no pan: the second click is near the centre")
    }

    func testClicksThatFitInOneViewAreFramedTogetherWithoutMovingTheCamera() {
        let r = zoom().generate(from: [click(5, 0.30, 0.50), click(6.5, 0.70, 0.50)])
        XCTAssertEqual(r.zooms, 1)
        XCTAssertEqual(r.points.count, 2, "in and out: nothing moves in between")
        XCTAssertEqual(r.points[0].scale, 1 / 0.6, accuracy: 0.001, "zoom lowered so both clicks stay in view (0.4 apart + margins)")
        XCTAssertEqual(r.points[0].center.x, 0.5, accuracy: 0.001, "centred between the two clicks")
    }

    func testClicksTooFarApartForOneViewMakeTheCameraGlide() {
        let r = zoom().generate(from: [click(5, 0.10, 0.50), click(6.5, 0.90, 0.50)])
        XCTAssertEqual(r.zooms, 1)
        XCTAssertEqual(r.points.count, 3, "in, one glide, out")
        XCTAssertEqual(r.points[1].scale, r.points[0].scale, accuracy: 0.001)
        XCTAssertGreaterThan(r.points[1].center.x, r.points[0].center.x)
    }

    func testClicksSpreadOverTheWholeScreenGetNoZoom() {
        let r = zoom().generate(from: [click(5, 0.05, 0.05), click(5.5, 0.95, 0.10), click(6, 0.50, 0.95)])
        XCTAssertTrue(r.points.isEmpty)
        XCTAssertEqual(r.zooms, 0)
    }

    func testALoneClickAlwaysGetsAZoom() {
        XCTAssertEqual(zoom().generate(from: [click(5, 0.9, 0.9)]).zooms, 1)
    }

    func testTwoZoomsCloseTogetherGlideWithoutZoomingOut() {
        // First zoom ends at 3.3, the second starts at 4.3: only 1.0 s apart (< 1.2 s), so they are linked.
        let r = zoom().generate(from: [click(2, 0.2, 0.2), click(4.8, 0.8, 0.8)])
        XCTAssertEqual(r.zooms, 2)
        let zoomOutsInTheMiddle = r.points.filter { $0.scale == 1 && $0.time < 6 }
        XCTAssertTrue(zoomOutsInTheMiddle.isEmpty, "the camera never returns to the wide shot between the two")
        XCTAssertEqual(r.points.last?.scale, 1, "but it zooms out at the very end")
    }

    func testTwoZoomsFarApartEachZoomOut() {
        let r = zoom().generate(from: [click(2, 0.2, 0.2), click(10, 0.8, 0.8)])
        XCTAssertEqual(r.zooms, 2)
        XCTAssertEqual(r.points.filter { $0.scale == 1 }.count, 2)
    }

    func testADoubleClickCountsOnce() {
        let r = zoom().generate(from: [click(5.00, 0.5, 0.5), click(5.12, 0.5, 0.5)])
        XCTAssertEqual(r.clicks, 1)
    }

    func testClicksOutsideTheTrimAreIgnored() {
        let r = zoom(range: 4...8).generate(from: [click(1, 0.5, 0.5), click(5, 0.5, 0.5), click(12, 0.5, 0.5)])
        XCTAssertEqual(r.clicks, 1)
        XCTAssertLessThanOrEqual(r.points.map(\.time).max() ?? 0, 8 - 0.05 + 0.0001)
    }

    func testClicksOutsideTheCropAreIgnoredAndTheRestIsRelativeToTheCrop() {
        let crop = CGRect(x: 0.5, y: 0, width: 0.5, height: 1)
        let r = zoom(base: crop).generate(from: [click(3, 0.2, 0.5), click(6, 0.75, 0.5)])
        XCTAssertEqual(r.clicks, 1)
        XCTAssertEqual(r.points[0].center.x, 0.5, accuracy: 0.001, "0.75 in the source is the middle of the right half")
    }

    func testPointsAreInOrderAndStayInsideTheRange() {
        let r = zoom(range: 0...12).generate(from: (0..<30).map { click(Double($0) * 0.4 + 0.5, Double($0 % 7) / 7, 0.4) })
        let times = r.points.map(\.time)
        XCTAssertEqual(times, times.sorted())
        XCTAssertGreaterThanOrEqual(times.min() ?? 0, 0)
        XCTAssertLessThanOrEqual(times.max() ?? 0, 12)
    }

    func testNoClicksNoZoom() {
        XCTAssertTrue(zoom().generate(from: []).points.isEmpty)
    }
}
