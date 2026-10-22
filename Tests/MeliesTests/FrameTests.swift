import CoreImage
import XCTest
@testable import Melies

final class FrameTests: XCTestCase {
    private let key = FrameStyle.key
    private var saved: Data?

    override func setUp() {
        super.setUp()
        saved = UserDefaults.standard.data(forKey: key)
    }

    override func tearDown() {
        if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        super.tearDown()
    }

    private func plan(natural: CGSize, frame: FrameStyle, maxWidth: Int = 1920, crop: CGRect? = nil) -> RenderPlan {
        let settings = ExportSettings(format: .mp4, maxMegabytes: nil, maxWidth: maxWidth, frame: frame)
        return VideoExport.makePlan(natural: natural, preferred: .identity, crop: crop, points: [], annotations: [], clicks: nil, settings: settings)
    }

    private var on: FrameStyle { FrameStyle(enabled: true, padding: 0.08, radius: 0.02, shadow: 0.5, preset: "aurora") }

    func testWithoutFrameTheCanvasIsThePicture() {
        let p = plan(natural: CGSize(width: 2560, height: 1440), frame: FrameStyle())
        XCTAssertEqual(p.canvas, CGSize(width: 1920, height: 1080))
        XCTAssertEqual(p.content, CGRect(x: 0, y: 0, width: 1920, height: 1080))
        XCTAssertNil(p.frameLayers)
    }

    func testFrameCanvasStaysWithinLimits() {
        for size in [CGSize(width: 2560, height: 1440), CGSize(width: 640, height: 360), CGSize(width: 1000, height: 1000),
                     CGSize(width: 3000, height: 600), CGSize(width: 400, height: 2400), CGSize(width: 1919, height: 1081)] {
            for width in [640, 1280, 1920] {
                let p = plan(natural: size, frame: on, maxWidth: width)
                // (Very tall pictures get padded sideways to reach 1:3, as without a frame, so they may pass maxWidth.)
                if size.height / size.width < 3 { XCTAssertLessThanOrEqual(p.canvas.width, CGFloat(width), "\(size) at \(width)") }
                XCTAssertEqual(p.canvas.width.truncatingRemainder(dividingBy: 2), 0)
                XCTAssertEqual(p.canvas.height.truncatingRemainder(dividingBy: 2), 0)
                XCTAssertLessThanOrEqual(p.canvas.width / p.canvas.height, 3.0001)
                XCTAssertLessThanOrEqual(p.canvas.height / p.canvas.width, 3.0001)
                XCTAssertNotNil(p.frameLayers)
                // The picture is inside the canvas.
                XCTAssertGreaterThanOrEqual(p.content.minX, 0)
                XCTAssertGreaterThanOrEqual(p.content.minY, 0)
                XCTAssertLessThanOrEqual(p.content.maxX, p.canvas.width)
                XCTAssertLessThanOrEqual(p.content.maxY, p.canvas.height)
            }
        }
    }

    func testFramePicturePaddingAndCentering() {
        let p = plan(natural: CGSize(width: 2560, height: 1440), frame: on)
        XCTAssertEqual(p.content.midX, p.canvas.width / 2, accuracy: 1)
        XCTAssertEqual(p.content.midY, p.canvas.height / 2, accuracy: 1)
        // Margin is 8 % of the picture width on each side.
        XCTAssertEqual(p.content.minX / p.content.width, 0.08, accuracy: 0.005)
        XCTAssertEqual(p.canvas.width, p.content.width * 1.16, accuracy: 3)
        // The picture is smaller than without a frame (the margins share the output width).
        XCTAssertLessThan(p.content.width, 1920)
    }

    func testExtremeAspectKeepsContentCentered() {
        let p = plan(natural: CGSize(width: 3000, height: 300), frame: on)
        XCTAssertLessThanOrEqual(p.canvas.width / p.canvas.height, 3.0001)
        XCTAssertEqual(p.content.midY, p.canvas.height / 2, accuracy: 1)
    }

    func testStyleRoundTrip() {
        let style = FrameStyle(enabled: true, padding: 0.12, radius: 0.03, shadow: 0.9, preset: "sunset")
        style.save()
        XCTAssertEqual(FrameStyle.load(), style)
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(FrameStyle.load(), FrameStyle())
    }

    func testPresetIDsAreUniqueAndResolvable() {
        let ids = FramePreset.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(FrameStyle(preset: "nope").fill.id, FramePreset.all[0].id)
        for id in ids { XCTAssertEqual(FrameStyle(preset: id).fill.id, id) }
    }

    /// Renders one framed frame to a PNG (MELIES_FRAME_PNG overrides the path) so it can be looked at,
    /// and checks a few pixels: background in the margin corner, picture in the middle, rounded corner showing the background.
    func testRenderedFrameHasMarginsRoundedCornersAndShadow() throws {
        let style = FrameStyle(enabled: true, padding: 0.1, radius: 0.04, shadow: 0.8, preset: "aurora")
        let p = plan(natural: CGSize(width: 1280, height: 720), frame: style, maxWidth: 1280)
        // A source with a bright corner marker so the rounding is visible.
        let checker = CIFilter(name: "CICheckerboardGenerator", parameters: [
            "inputWidth": 40, "inputColor0": CIColor(red: 1, green: 0.9, blue: 0.2), "inputColor1": CIColor(red: 0.95, green: 0.3, blue: 0.2),
            "inputCenter": CIVector(x: 0, y: 0),
        ])!.outputImage!.cropped(to: CGRect(x: 0, y: 0, width: 1280, height: 720))
        let out = p.render(checker, at: 0)
        let rect = CGRect(origin: .zero, size: p.canvas)
        let cg = try XCTUnwrap(RenderContext.shared.createCGImage(out, from: rect, format: .RGBA8, colorSpace: RenderContext.sRGB))

        let path = ProcessInfo.processInfo.environment["MELIES_FRAME_PNG"] ?? NSTemporaryDirectory() + "melies-frame.png"
        let rep = NSBitmapImageRep(cgImage: cg)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))

        func pixel(_ x: Int, _ y: Int) -> (r: CGFloat, g: CGFloat, b: CGFloat) {
            let c = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            return (c.redComponent, c.greenComponent, c.blueComponent)
        }
        // Top-left pixel of the canvas: the gradient start (violet-blue), not the picture.
        let corner = pixel(2, 2)
        XCTAssertGreaterThan(corner.b, corner.r - 0.1)
        XCTAssertLessThan(corner.g, 0.6)
        // The very first pixel of the picture corner shows the background (rounded), the middle shows the checkerboard.
        let c = p.content
        let cornerOfPicture = pixel(Int(c.minX) + 1, Int(c.minY) + 1)
        XCTAssertLessThan(cornerOfPicture.g, 0.6, "the picture corner is rounded, so the background shows through")
        let middle = pixel(Int(c.midX), Int(c.midY))
        XCTAssertGreaterThan(middle.r, 0.9, "the picture itself")
    }
}
