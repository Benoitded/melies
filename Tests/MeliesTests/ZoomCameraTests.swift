import XCTest
@testable import Melies

final class ZoomCameraTests: XCTestCase {
    private func point(_ time: Double, _ scale: Double, _ x: Double = 0.5, _ y: Double = 0.5, transition: Double = 1, ease: ZoomEase = .linear) -> ZoomPoint {
        ZoomPoint(time: time, scale: scale, center: CGPoint(x: x, y: y), transition: transition, ease: ease)
    }

    // MARK: eases

    func testEveryEaseStartsAtZeroAndEndsAtOne() {
        for ease in ZoomEase.allCases {
            XCTAssertEqual(ease.apply(0), 0, accuracy: 1e-12, "\(ease)")
            XCTAssertEqual(ease.apply(1), 1, accuracy: 1e-12, "\(ease)")
        }
    }

    func testEasesClampTheirInput() {
        for ease in ZoomEase.allCases {
            XCTAssertEqual(ease.apply(-4), ease.apply(0), "\(ease)")
            XCTAssertEqual(ease.apply(9), ease.apply(1), "\(ease)")
        }
    }

    func testEasesAreMonotonicExceptTheSpringOvershoot() {
        for ease in [ZoomEase.linear, .smooth, .snappy] {
            var last = -1.0
            for i in 0...200 {
                let v = ease.apply(Double(i) / 200)
                XCTAssertGreaterThanOrEqual(v, last, "\(ease) at \(i)")
                XCTAssertLessThanOrEqual(v, 1 + 1e-12, "\(ease)")
                last = v
            }
        }
        XCTAssertGreaterThan((0...200).map { ZoomEase.spring.apply(Double($0) / 200) }.max()!, 1.01, "the spring overshoots")
    }

    func testEaseShapes() {
        XCTAssertEqual(ZoomEase.linear.apply(0.3), 0.3, accuracy: 1e-12)
        XCTAssertEqual(ZoomEase.smooth.apply(0.5), 0.5, accuracy: 1e-12, "smooth is symmetric")
        XCTAssertLessThan(ZoomEase.smooth.apply(0.25), 0.25, "smooth starts slowly")
        XCTAssertGreaterThan(ZoomEase.snappy.apply(0.25), 0.25, "snappy starts fast")
        XCTAssertEqual(ZoomEase.snappy.apply(0.5), 1 - pow(0.5, 5), accuracy: 1e-12)
        XCTAssertEqual(ZoomEase.allCases.map(\.labelKey), ["ease.smooth", "ease.snappy", "ease.linear", "ease.spring"])
    }

    // MARK: state(at:points:)

    func testWithoutPointsTheCameraRests() {
        XCTAssertEqual(ZoomCamera.state(at: 3, points: []), ZoomCamera.rest)
    }

    func testTheCameraRestsUntilTheTravelStarts() {
        let p = [point(5, 2, 0.3, 0.3, transition: 1)]
        XCTAssertEqual(ZoomCamera.state(at: 0, points: p), ZoomCamera.rest)
        XCTAssertEqual(ZoomCamera.state(at: -10, points: p), ZoomCamera.rest)
        XCTAssertEqual(ZoomCamera.state(at: 4, points: p), ZoomCamera.rest, "the travel starts exactly at time - transition")
    }

    func testTheCameraArrivesAtTheTimeOfThePointAndHolds() {
        let p = [point(5, 2, 0.3, 0.3)]
        let arrived = ZoomCamera.state(at: 5, points: p)
        XCTAssertEqual(arrived.scale, 2, accuracy: 1e-12)
        XCTAssertEqual(arrived.center.x, 0.3, accuracy: 1e-12)
        XCTAssertEqual(ZoomCamera.state(at: 500, points: p), arrived, "it holds the last value forever")
    }

    func testTheTravelIsLogarithmicInScale() {
        let p = [point(5, 4, 0.5, 0.5, transition: 2, ease: .linear)]
        XCTAssertEqual(ZoomCamera.state(at: 4, points: p).scale, 2, accuracy: 1e-9, "half way from 1 to 4 is 2, not 2.5")
        XCTAssertEqual(ZoomCamera.state(at: 3.5, points: p).scale, pow(4, 0.25), accuracy: 1e-9)
        // Zooming out is the mirror image.
        let out = [point(1, 4, transition: 0.5), point(5, 1, transition: 2, ease: .linear)]
        XCTAssertEqual(ZoomCamera.state(at: 4, points: out).scale, 2, accuracy: 1e-9)
    }

    func testTheCenterTravelsLinearlyWithTheEase() {
        let p = [point(5, 2, 0.75, 0.25, transition: 2, ease: .linear)]
        let mid = ZoomCamera.state(at: 4, points: p)
        // from (0.5, 0.5) to (0.75, 0.25): half way is (0.625, 0.375), inside the allowed range at scale ~1.41
        XCTAssertEqual(mid.center.x, 0.625, accuracy: 1e-9)
        XCTAssertEqual(mid.center.y, 0.375, accuracy: 1e-9)
    }

    func testEachEaseDrivesTheTravel() {
        for ease in ZoomEase.allCases {
            let p = [point(5, 2, 0.5, 0.5, transition: 2, ease: ease)]
            let expected = exp(log(2.0) * ease.apply(0.5))
            XCTAssertEqual(ZoomCamera.state(at: 4, points: p).scale, max(expected, 1), accuracy: 1e-9, "\(ease)")
            XCTAssertEqual(ZoomCamera.state(at: 3, points: p).scale, 1, accuracy: 1e-12, "\(ease) start")
            XCTAssertEqual(ZoomCamera.state(at: 5, points: p).scale, 2, accuracy: 1e-12, "\(ease) end")
        }
    }

    func testThePointCenterIsClampedSoTheViewStaysInTheFrame() {
        let s = ZoomCamera.state(at: 5, points: [point(5, 2, 0, 1)])
        XCTAssertEqual(s.center.x, 0.25, accuracy: 1e-12)
        XCTAssertEqual(s.center.y, 0.75, accuracy: 1e-12)
    }

    func testBetweenTwoPointsTheCameraHoldsUntilTheNextTravel() {
        let p = [point(2, 2, 0.3, 0.3, transition: 0.5), point(8, 3, 0.7, 0.7, transition: 1)]
        let held = ZoomCamera.state(at: 2, points: p)
        for t in [2.0, 3, 5, 6.99] { XCTAssertEqual(ZoomCamera.state(at: t, points: p), held, "t=\(t)") }
        XCTAssertGreaterThan(ZoomCamera.state(at: 7.5, points: p).scale, 2)
        XCTAssertEqual(ZoomCamera.state(at: 8, points: p).scale, 3, accuracy: 1e-12)
    }

    func testATransitionLongerThanTheGapStartsAtThePreviousPoint() {
        // The second point wants 5 s of travel but only 1 s separates it from the first.
        let p = [point(2, 2, transition: 0.5), point(3, 4, transition: 5, ease: .linear)]
        XCTAssertEqual(ZoomCamera.state(at: 2, points: p).scale, 2, accuracy: 1e-12)
        XCTAssertEqual(ZoomCamera.state(at: 2.5, points: p).scale, sqrt(2 * 4), accuracy: 1e-9, "half way between 2 and 4, in log scale")
        XCTAssertEqual(ZoomCamera.state(at: 3, points: p).scale, 4, accuracy: 1e-12)
    }

    func testAZeroTransitionJumps() {
        let p = [point(4, 3, transition: 0)]
        XCTAssertEqual(ZoomCamera.state(at: 3.999, points: p), ZoomCamera.rest)
        XCTAssertEqual(ZoomCamera.state(at: 4.001, points: p).scale, 3, accuracy: 1e-12) // at exactly 4 it is still the previous state (t <= start)
    }

    func testEveryStateStaysInsideTheFrameWithEveryEase() {
        for ease in ZoomEase.allCases {
            let points = [point(1, 4, 0, 0, transition: 0.8, ease: ease), point(3, 1, 0.5, 0.5, transition: 1, ease: ease),
                          point(6, 8, 1, 1, transition: 1.5, ease: ease), point(7, 1.2, 0.9, 0.1, transition: 3, ease: ease)]
            for i in 0...400 {
                let t = -1 + Double(i) * 0.025
                let s = ZoomCamera.state(at: t, points: points)
                XCTAssertGreaterThanOrEqual(s.scale, 1, "\(ease) t=\(t)")
                XCTAssertTrue(s.scale.isFinite && s.center.x.isFinite && s.center.y.isFinite, "\(ease) t=\(t)")
                let r = ZoomCamera.region(of: s, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                XCTAssertGreaterThanOrEqual(r.minX, -1e-9, "\(ease) t=\(t)")
                XCTAssertGreaterThanOrEqual(r.minY, -1e-9, "\(ease) t=\(t)")
                XCTAssertLessThanOrEqual(r.maxX, 1 + 1e-9, "\(ease) t=\(t)")
                XCTAssertLessThanOrEqual(r.maxY, 1 + 1e-9, "\(ease) t=\(t)")
            }
        }
    }

    // MARK: clampedCenter / region

    func testClampedCenter() {
        XCTAssertEqual(ZoomCamera.clampedCenter(CGPoint(x: 0.5, y: 0.5), scale: 1), CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(ZoomCamera.clampedCenter(CGPoint(x: 0, y: 1), scale: 2), CGPoint(x: 0.25, y: 0.75))
        XCTAssertEqual(ZoomCamera.clampedCenter(CGPoint(x: -4, y: 9), scale: 4), CGPoint(x: 0.125, y: 0.875))
        XCTAssertEqual(ZoomCamera.clampedCenter(CGPoint(x: 0.1, y: 0.9), scale: 0.5), CGPoint(x: 0.5, y: 0.5), "a scale below 1 is treated as 1")
        XCTAssertEqual(ZoomCamera.clampedCenter(CGPoint(x: 0.3, y: 0.6), scale: 2), CGPoint(x: 0.3, y: 0.6), "inside: untouched")
    }

    func testClampedCenterIsIdempotent() {
        for s in stride(from: 1.0, through: 8, by: 0.5) {
            for x in stride(from: -0.5, through: 1.5, by: 0.25) {
                let once = ZoomCamera.clampedCenter(CGPoint(x: x, y: 1 - x), scale: s)
                XCTAssertEqual(ZoomCamera.clampedCenter(once, scale: s), once)
            }
        }
    }

    func testRegionAtRestIsTheWholeBase() {
        XCTAssertEqual(ZoomCamera.region(of: ZoomCamera.rest, in: CGRect(x: 0, y: 0, width: 1, height: 1)), CGRect(x: 0, y: 0, width: 1, height: 1))
        let base = CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.6)
        let r = ZoomCamera.region(of: ZoomCamera.rest, in: base)
        XCTAssertEqual(r.minX, base.minX, accuracy: 1e-12)
        XCTAssertEqual(r.width, base.width, accuracy: 1e-12)
        XCTAssertEqual(r.height, base.height, accuracy: 1e-12)
    }

    func testRegionAtTwiceTheZoom() {
        let r = ZoomCamera.region(of: CameraState(scale: 2, center: CGPoint(x: 0.25, y: 0.75)), in: CGRect(x: 0, y: 0, width: 1, height: 1))
        XCTAssertEqual(r.minX, 0, accuracy: 1e-12)
        XCTAssertEqual(r.minY, 0.5, accuracy: 1e-12)
        XCTAssertEqual(r.width, 0.5, accuracy: 1e-12)
        XCTAssertEqual(r.height, 0.5, accuracy: 1e-12)
    }

    func testRegionStaysInsideTheFrameForEveryScaleAndCenter() {
        let bases = [CGRect(x: 0, y: 0, width: 1, height: 1), CGRect(x: 0.2, y: 0.1, width: 0.5, height: 0.6), CGRect(x: 0.9, y: 0.9, width: 0.1, height: 0.1)]
        for base in bases {
            for scale in stride(from: 1.0, through: 8.0, by: 0.25) {
                for cx in stride(from: 0.0, through: 1.0, by: 0.05) {
                    for cy in stride(from: 0.0, through: 1.0, by: 0.05) {
                        let center = ZoomCamera.clampedCenter(CGPoint(x: cx, y: cy), scale: scale)
                        let r = ZoomCamera.region(of: CameraState(scale: scale, center: center), in: base)
                        let label = "scale \(scale) center (\(cx), \(cy)) base \(base)"
                        XCTAssertGreaterThanOrEqual(r.minX, base.minX - 1e-9, label)
                        XCTAssertGreaterThanOrEqual(r.minY, base.minY - 1e-9, label)
                        XCTAssertLessThanOrEqual(r.maxX, base.maxX + 1e-9, label)
                        XCTAssertLessThanOrEqual(r.maxY, base.maxY + 1e-9, label)
                        XCTAssertEqual(r.width, base.width / scale, accuracy: 1e-9, label)
                        XCTAssertEqual(r.height, base.height / scale, accuracy: 1e-9, label)
                    }
                }
            }
        }
    }
}
