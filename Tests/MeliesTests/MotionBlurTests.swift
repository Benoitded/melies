import AppKit
import CoreImage
import XCTest
@testable import Melies

final class MotionBlurTests: XCTestCase {
    private func point(_ time: Double, scale: Double, x: Double = 0.5, y: Double = 0.5, transition: Double = 1) -> ZoomPoint {
        ZoomPoint(time: time, scale: scale, center: CGPoint(x: x, y: y), transition: transition, ease: .linear)
    }

    // MARK: velocity

    func testAStillCameraHasZeroVelocity() {
        XCTAssertEqual(MotionBlur.velocity(at: 0.5, points: []), .zero)
        let held = [point(1, scale: 2)]
        XCTAssertEqual(MotionBlur.velocity(at: 5, points: held), .zero) // after the travel
        XCTAssertEqual(MotionBlur.velocity(at: -3, points: held), .zero) // before the travel
    }

    func testAZoomInRampHasPositiveLogScaleVelocity() {
        // linear ease, scale 1 -> e over 1 s: log-scale speed is exactly 1 per second
        let v = MotionBlur.velocity(at: 0.5, points: [point(1, scale: M_E)])
        XCTAssertEqual(v.logScale, 1, accuracy: 1e-6)
        XCTAssertEqual(v.center.dx, 0, accuracy: 1e-9)
        XCTAssertEqual(v.center.dy, 0, accuracy: 1e-9)
    }

    func testAZoomOutHasNegativeVelocity() {
        let v = MotionBlur.velocity(at: 3.5, points: [point(1, scale: 2), point(4, scale: 1, transition: 1)])
        XCTAssertLessThan(v.logScale, 0)
        XCTAssertEqual(v.logScale, -log(2), accuracy: 1e-6)
    }

    func testAPurePanPointsInTheCenterDirection() {
        // Same scale, center moves right and down by 0.1 over 1 s (inside the clamp for scale 2).
        let points = [point(0.5, scale: 2, x: 0.5, y: 0.5, transition: 0.01), point(2, scale: 2, x: 0.6, y: 0.6, transition: 1)]
        let v = MotionBlur.velocity(at: 1.5, points: points)
        XCTAssertEqual(v.logScale, 0, accuracy: 1e-9)
        XCTAssertEqual(v.center.dx, 0.1, accuracy: 1e-6)
        XCTAssertEqual(v.center.dy, 0.1, accuracy: 1e-6)
        let left = MotionBlur.velocity(at: 1.5, points: [point(0.5, scale: 2, x: 0.5, y: 0.5, transition: 0.01), point(2, scale: 2, x: 0.4, y: 0.5, transition: 1)])
        XCTAssertLessThan(left.center.dx, 0)
        XCTAssertEqual(left.center.dy, 0, accuracy: 1e-9)
    }

    // MARK: parameters

    private let canvas1080 = CGSize(width: 1920, height: 1080)

    func testNoParamsWhenOffOrStill() {
        let fast = CameraVelocity(logScale: 3, center: CGVector(dx: 1, dy: 0))
        XCTAssertNil(MotionBlur.params(velocity: fast, scale: 2, content: canvas1080, canvas: canvas1080, level: .off))
        XCTAssertNil(MotionBlur.params(velocity: .zero, scale: 2, content: canvas1080, canvas: canvas1080, level: .strong))
    }

    func testParamsAreClampedAndScaleWithOutputSize() {
        let huge = CameraVelocity(logScale: 100, center: CGVector(dx: 100, dy: 100))
        let big = MotionBlur.params(velocity: huge, scale: 2, content: canvas1080, canvas: canvas1080, level: .strong)!
        XCTAssertEqual(big.zoomAmount, 24, accuracy: 1e-9)
        XCTAssertEqual(big.panRadius, 24, accuracy: 1e-9)
        let small = CGSize(width: 960, height: 540)
        let half = MotionBlur.params(velocity: huge, scale: 2, content: small, canvas: small, level: .strong)!
        XCTAssertEqual(half.zoomAmount, 12, accuracy: 1e-9)
        XCTAssertEqual(half.panRadius, 12, accuracy: 1e-9)
        let light = MotionBlur.params(velocity: huge, scale: 2, content: canvas1080, canvas: canvas1080, level: .light)!
        XCTAssertLessThan(light.zoomAmount, big.zoomAmount)
    }

    func testStrongBlursMoreThanLightAndAngleFollowsThePan() {
        let v = CameraVelocity(logScale: 0, center: CGVector(dx: 0.3, dy: 0))
        let light = MotionBlur.params(velocity: v, scale: 2, content: canvas1080, canvas: canvas1080, level: .light)!
        let strong = MotionBlur.params(velocity: v, scale: 2, content: canvas1080, canvas: canvas1080, level: .strong)!
        XCTAssertGreaterThan(strong.panRadius, light.panRadius)
        XCTAssertEqual(light.zoomAmount, 0)
        XCTAssertEqual(light.panAngle, 0, accuracy: 1e-9) // camera moves right
        let down = CameraVelocity(logScale: 0, center: CGVector(dx: 0, dy: 0.3))
        let d = MotionBlur.params(velocity: down, scale: 2, content: canvas1080, canvas: canvas1080, level: .strong)!
        XCTAssertEqual(d.panAngle, -.pi / 2, accuracy: 1e-9) // y is flipped in Core Image
    }

    func testTinyMotionIsIgnored() {
        let v = CameraVelocity(logScale: 0.01, center: .zero)
        XCTAssertNil(MotionBlur.params(velocity: v, scale: 1, content: canvas1080, canvas: canvas1080, level: .light))
    }

    func testLevelParsingAndDefault() {
        XCTAssertEqual(MotionBlurLevel.default, .light)
        XCTAssertEqual(MotionBlurLevel.allCases.map(\.rawValue), ["off", "light", "strong"])
    }

    // MARK: rendering

    private func source() -> CIImage {
        CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputWidth": 40, "inputColor0": CIColor(red: 1, green: 0.9, blue: 0.2), "inputColor1": CIColor(red: 0.1, green: 0.3, blue: 0.8),
            "inputCenter": CIVector(x: 0, y: 0),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
    }

    private func plan(level: MotionBlurLevel, points: [ZoomPoint]) -> RenderPlan {
        var settings = ExportSettings(format: .mp4, maxMegabytes: nil, maxWidth: 1280)
        settings.motionBlur = level
        return VideoExport.makePlan(natural: CGSize(width: 1280, height: 720), preferred: .identity, crop: nil, points: points,
                                    annotations: [], clicks: nil, settings: settings)
    }

    private func pixels(_ p: RenderPlan, at t: Double) throws -> (CGImage, Data) {
        let out = p.render(source(), at: t)
        let cg = try XCTUnwrap(RenderContext.shared.createCGImage(out, from: CGRect(origin: .zero, size: p.canvas), format: .RGBA8, colorSpace: RenderContext.sRGB))
        return (cg, try XCTUnwrap(cg.dataProvider?.data as Data?))
    }

    func testStillCameraIsPixelIdenticalWithAndWithoutBlur() throws {
        let points = [point(2, scale: 2, x: 0.3, y: 0.4)]
        for t in [0.0, 0.5, 5.0] { // before the travel (starts at 1 s) and after it
            let off = try pixels(plan(level: .off, points: points), at: t)
            let on = try pixels(plan(level: .strong, points: points), at: t)
            XCTAssertEqual(off.1, on.1, "t = \(t)")
        }
    }

    func testAFastZoomBlursButKeepsTheSize() throws {
        let points = [point(1, scale: 3, transition: 0.4)]
        let off = try pixels(plan(level: .off, points: points), at: 0.8)
        let on = try pixels(plan(level: .strong, points: points), at: 0.8)
        XCTAssertEqual(off.0.width, on.0.width)
        XCTAssertEqual(off.0.height, on.0.height)
        XCTAssertNotEqual(off.1, on.1, "a moving camera must smear the picture")

        let path = ProcessInfo.processInfo.environment["MELIES_MOTIONBLUR_PNG"] ?? NSTemporaryDirectory() + "melies-motionblur.png"
        let rep = NSBitmapImageRep(cgImage: on.0)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
    }

    func testAPanBlursButKeepsTheSize() throws {
        let points = [point(0.2, scale: 2, x: 0.3, y: 0.3, transition: 0.01), point(1.2, scale: 2, x: 0.8, y: 0.7, transition: 0.5)]
        let off = try pixels(plan(level: .off, points: points), at: 0.95)
        let on = try pixels(plan(level: .light, points: points), at: 0.95)
        XCTAssertEqual(off.0.width, on.0.width)
        XCTAssertNotEqual(off.1, on.1)
    }
}
