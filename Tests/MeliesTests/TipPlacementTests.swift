import XCTest
@testable import Melies

final class TipPlacementTests: XCTestCase {
    private let window = CGSize(width: 1000, height: 640)
    private let tip = CGSize(width: 120, height: 40)

    func testTopOfTheWindowShowsBelow() {
        let r = TipPlacement.resolve(control: CGRect(x: 100, y: 20, width: 34, height: 30), window: window, tip: tip)
        XCTAssertFalse(r.above); XCTAssertFalse(r.anchorRight)
    }

    func testBottomBarShowsAbove() {
        let r = TipPlacement.resolve(control: CGRect(x: 100, y: 580, width: 34, height: 40), window: window, tip: tip)
        XCTAssertTrue(r.above)
    }

    func testBottomRightCornerShowsAboveAndAnchorsRight() {
        let r = TipPlacement.resolve(control: CGRect(x: 960, y: 590, width: 34, height: 34), window: window, tip: CGSize(width: 200, height: 40))
        XCTAssertTrue(r.above); XCTAssertTrue(r.anchorRight)
    }

    func testNoRoomAnywhereStaysBelow() {
        let r = TipPlacement.resolve(control: CGRect(x: 10, y: 5, width: 34, height: 30), window: CGSize(width: 300, height: 60), tip: CGSize(width: 120, height: 80))
        XCTAssertFalse(r.above)
    }

    func testForceRight() {
        XCTAssertTrue(TipPlacement.resolve(control: CGRect(x: 10, y: 10, width: 30, height: 30), window: window, tip: tip, forceRight: true).anchorRight)
    }
}
