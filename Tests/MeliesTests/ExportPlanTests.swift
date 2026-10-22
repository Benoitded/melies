import XCTest
@testable import Melies

final class ExportPlanTests: XCTestCase {
    private func plan(_ w: CGFloat, _ h: CGFloat, preferred: CGAffineTransform = .identity, crop: CGRect? = nil, maxWidth: Int = 1920,
                      points: [ZoomPoint] = []) -> RenderPlan {
        VideoExport.makePlan(natural: CGSize(width: w, height: h), preferred: preferred, crop: crop, points: points, annotations: [], clicks: nil,
                             settings: ExportSettings(format: .mp4, maxMegabytes: nil, maxWidth: maxWidth))
    }

    private func assertEvenAndInside(_ p: RenderPlan, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Int(p.canvas.width) % 2, 0, "canvas width \(p.canvas.width) must be even", file: file, line: line)
        XCTAssertEqual(Int(p.canvas.height) % 2, 0, "canvas height \(p.canvas.height) must be even", file: file, line: line)
        XCTAssertGreaterThan(p.canvas.width, 0, file: file, line: line)
        XCTAssertGreaterThan(p.canvas.height, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(p.content.minX, 0, file: file, line: line)
        XCTAssertGreaterThanOrEqual(p.content.minY, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(p.content.maxX, p.canvas.width, file: file, line: line)
        XCTAssertLessThanOrEqual(p.content.maxY, p.canvas.height, file: file, line: line)
    }

    func testAFullHDSourceIsKeptAsIs() {
        let p = plan(1920, 1080)
        XCTAssertEqual(p.canvas, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(p.content, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(p.base, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertEqual(p.uprightSize, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(p.orientation, .up)
    }

    func testABiggerSourceIsScaledDownToMaxWidth() {
        for maxWidth in ExportSettings.widthChoices {
            let p = plan(3840, 2160, maxWidth: maxWidth)
            XCTAssertEqual(p.canvas.width, CGFloat(maxWidth))
            XCTAssertEqual(p.canvas.height, (CGFloat(maxWidth) * 9 / 16 / 2).rounded() * 2, accuracy: 2)
            assertEvenAndInside(p)
        }
    }

    func testASmallerSourceIsNeverUpscaled() {
        let p = plan(1000, 500)
        XCTAssertEqual(p.canvas, CGSize(width: 1000, height: 500))
    }

    func testAnOddSourceGivesEvenDimensions() {
        let p = plan(1001, 777)
        assertEvenAndInside(p)
        XCTAssertEqual(p.canvas, CGSize(width: 1002, height: 778))
    }

    func testAWideSourcePastThreeToOneIsPaddedVertically() {
        let p = plan(3000, 500) // 6:1
        // scaled to 1920 x 320, then padded to 1920 / 3 = 640 high
        XCTAssertEqual(p.canvas, CGSize(width: 1920, height: 640))
        XCTAssertEqual(p.content, CGRect(x: 0, y: 160, width: 1920, height: 320))
        XCTAssertLessThanOrEqual(p.canvas.width / p.canvas.height, 3.0001)
        assertEvenAndInside(p)
    }

    func testATallSourcePastOneToThreeIsPaddedHorizontally() {
        let p = plan(500, 3000) // 1:6, not scaled (height 3000 <= 8192, width < 1920)
        XCTAssertEqual(p.canvas, CGSize(width: 1000, height: 3000))
        XCTAssertEqual(p.content, CGRect(x: 250, y: 0, width: 500, height: 3000))
        XCTAssertLessThanOrEqual(p.canvas.height / p.canvas.width, 3.0001)
        assertEvenAndInside(p)
    }

    func testExactlyThreeToOneNeedsNoPadding() {
        XCTAssertEqual(plan(1800, 600).canvas, CGSize(width: 1800, height: 600))
        XCTAssertEqual(plan(600, 1800).canvas, CGSize(width: 600, height: 1800))
    }

    func testTheContentIsCenteredInTheCanvas() {
        for (w, h) in [(3000.0, 500.0), (500.0, 3000.0), (1920.0, 1080.0), (4000.0, 900.0), (777.0, 3333.0)] {
            let p = plan(w, h)
            XCTAssertEqual(p.content.minX, p.canvas.width - p.content.maxX, accuracy: 0.0001, "\(w)x\(h)")
            XCTAssertEqual(p.content.minY, p.canvas.height - p.content.maxY, accuracy: 0.0001, "\(w)x\(h)")
        }
    }

    func testTheHeightIsCappedAt8192() {
        let p = plan(100, 1_000_000)
        XCTAssertLessThanOrEqual(p.canvas.height, 8192 + 2)
        assertEvenAndInside(p)
    }

    func testARotatedTrackSwapsWidthAndHeightAndKeepsTheOrientation() {
        // iPhone portrait clip: stored 1920 x 1080, rotated a quarter turn clockwise.
        let right = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let p = plan(1920, 1080, preferred: right)
        XCTAssertEqual(p.uprightSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(p.orientation, .right)
        XCTAssertEqual(p.canvas, CGSize(width: 1080, height: 1920))

        let left = CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: 1920)
        XCTAssertEqual(plan(1920, 1080, preferred: left).orientation, .left)
        XCTAssertEqual(plan(1920, 1080, preferred: left).uprightSize, CGSize(width: 1080, height: 1920))

        let down = CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: 1920, ty: 1080)
        let d = plan(1920, 1080, preferred: down)
        XCTAssertEqual(d.orientation, .down)
        XCTAssertEqual(d.uprightSize, CGSize(width: 1920, height: 1080))
    }

    func testARotatedTrackIsCappedByMaxWidthOnItsUprightWidth() {
        let right = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 2160, ty: 0)
        let p = plan(3840, 2160, preferred: right, maxWidth: 1280) // upright 2160 x 3840 -> 1280 wide
        XCTAssertEqual(p.canvas.width, 1280)
        XCTAssertEqual(p.canvas.height, 2276, accuracy: 2) // 3840 * 1280 / 2160 = 2275.6
        assertEvenAndInside(p)
    }

    func testACropIsExpressedInUprightPixels() {
        let p = plan(1920, 1080, crop: CGRect(x: 0.25, y: 0.5, width: 0.5, height: 0.25))
        XCTAssertEqual(p.base, CGRect(x: 480, y: 540, width: 960, height: 270))
        XCTAssertEqual(p.canvas, CGSize(width: 960, height: 320)) // 960 / 3 = 320: a 3.55:1 crop is padded
        XCTAssertEqual(p.content, CGRect(x: 0, y: 25, width: 960, height: 270))
    }

    func testACropOnARotatedTrackUsesTheUprightFrame() {
        let right = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
        let p = plan(1920, 1080, preferred: right, crop: CGRect(x: 0, y: 0, width: 1, height: 0.5))
        XCTAssertEqual(p.base, CGRect(x: 0, y: 0, width: 1080, height: 960))
    }

    func testOddCropSizesStayEven() {
        for (cw, ch) in [(0.333, 0.777), (0.1234, 0.9999), (0.5, 0.5), (0.99, 0.01), (0.01, 0.99)] {
            let p = plan(1919, 1079, crop: CGRect(x: 0.1, y: 0.0, width: cw, height: ch))
            assertEvenAndInside(p)
            XCTAssertLessThanOrEqual(p.canvas.width / p.canvas.height, 3.01, "\(cw)x\(ch)")
            XCTAssertLessThanOrEqual(p.canvas.height / p.canvas.width, 3.01, "\(cw)x\(ch)")
        }
    }

    func testACropNeverCollapsesBelowTwoPixels() {
        let p = plan(1920, 1080, crop: CGRect(x: 0.5, y: 0.5, width: 0.0001, height: 0.0001))
        XCTAssertGreaterThanOrEqual(p.base.width, 2)
        XCTAssertGreaterThanOrEqual(p.base.height, 2)
        assertEvenAndInside(p)
    }

    func testEveryCanvasStaysEvenAndPaddedAcrossAGridOfSources() {
        for w in stride(from: 3, through: 9000, by: 877) {
            for h in stride(from: 5, through: 9000, by: 911) {
                for maxWidth in [640, 1920] {
                    let p = plan(CGFloat(w), CGFloat(h), maxWidth: maxWidth)
                    assertEvenAndInside(p)
                    XCTAssertLessThanOrEqual(p.canvas.height, 8192 + 2, "\(w)x\(h)")
                    XCTAssertLessThanOrEqual(p.canvas.width / p.canvas.height, 3.01, "\(w)x\(h)")
                    XCTAssertLessThanOrEqual(p.canvas.height / p.canvas.width, 3.01, "\(w)x\(h)")
                }
            }
        }
    }

    func testTheZoomPointsAreSortedByTime() {
        let a = ZoomPoint(time: 5, scale: 2, center: CGPoint(x: 0.5, y: 0.5), transition: 0.5, ease: .smooth)
        let b = ZoomPoint(time: 1, scale: 3, center: CGPoint(x: 0.5, y: 0.5), transition: 0.5, ease: .linear)
        XCTAssertEqual(plan(1920, 1080, points: [a, b]).points.map(\.time), [1, 5])
    }

    // MARK: Known problems

    /// `maxWidth` is the width limit of the export (the settings call it "resolution"), but a tall source
    /// that is padded to 1:3 gets a canvas wider than it: 600 x 6000 is not scaled (it fits), then padded to 2000 wide.
    func testAPaddedTallCanvasStaysWithinMaxWidth() {
        let p = plan(600, 6000, maxWidth: 1920)
        XCTExpectFailure("makePlan pads a 1:10 source to 2000 px wide, above maxWidth 1920 (Export.swift, the `contentH / contentW > 3` branch)") {
            XCTAssertLessThanOrEqual(p.canvas.width, 1920)
        }
    }

    /// A 2 px wide crop of a very tall video: the content width rounds to 0 once scaled to the 8192 height cap.
    func testAnExtremelyThinSourceStillHasAVisibleContentRect() {
        let p = plan(2, 1_000_000)
        XCTExpectFailure("content.width is 0 when width * 8192 / height rounds below 1 (Export.swift contentW)") {
            XCTAssertGreaterThan(p.content.width, 0)
        }
    }
}
