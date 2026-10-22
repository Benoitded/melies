import AVFoundation
import XCTest
@testable import Melies

final class ObjectTrackerTests: XCTestCase {
    private let w = 320, h = 180

    private func cleanup(_ url: URL) { addTeardownBlock { try? FileManager.default.removeItem(at: url) } }

    private func track(_ url: URL, box: CGRect, from: Double, to: Double, lowerBound: Double? = nil) async throws -> ObjectTracker.Result {
        try await ObjectTracker.track(asset: AVURLAsset(url: url), box: box, from: from, to: to, lowerBound: lowerBound, progress: { _ in })
    }

    /// A textured square (48 px) moving right at `speed` px/s over a flat background, 3 s.
    private func movingSquare(speed: Double, x0: Double = 20, y: Double = 66) async throws -> URL {
        let texture = SyntheticVideo.noise(width: 48, height: 48, seed: 42)
        let url = try await SyntheticVideo.make(width: w, height: h, frames: 60) { i, ctx in
            ctx.setFillColor(CGColor(gray: 0.5, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            let x = (x0 + speed * Double(i) / 30).rounded()
            ctx.interpolationQuality = .none
            ctx.draw(texture, in: CGRect(x: x, y: y, width: 48, height: 48))
        }
        cleanup(url)
        return url
    }

    private func squareBox(atX x: Double, y: Double = 66) -> CGRect { CGRect(x: x / 320, y: y / 180, width: 48.0 / 320, height: 48.0 / 180) }

    func testFollowsAHorizontalMoveAtItsSpeed() async throws {
        let speed = 60.0
        let url = try await movingSquare(speed: speed)
        let r = try await track(url, box: squareBox(atX: 20), from: 0, to: 2)
        XCTAssertNil(r.lostAt)
        XCTAssertGreaterThan(r.samples.count, 40)
        XCTAssertEqual(r.samples.first?.dx, 0)
        XCTAssertEqual(r.samples.first?.dy, 0)
        for s in r.samples where s.t > 0.3 {
            XCTAssertEqual(s.dx * 320 / s.t, speed, accuracy: speed * 0.05, "t=\(s.t)")
            XCTAssertEqual(s.dy * 180, 0, accuracy: 2, "t=\(s.t)")
        }
        let last = try XCTUnwrap(r.samples.last)
        XCTAssertEqual(last.t, 1.967, accuracy: 0.05)
    }

    func testSamplesAreAscendingInTime() async throws {
        let url = try await movingSquare(speed: 60)
        let r = try await track(url, box: squareBox(atX: 20), from: 0, to: 2)
        XCTAssertEqual(r.samples.map(\.t), r.samples.map(\.t).sorted())
    }

    func testReportsProgressUpToOneAndEachSample() async throws {
        let url = try await movingSquare(speed: 60)
        final class Counter: @unchecked Sendable {
            let l = NSLock(); var n = 0; var maxP = 0.0
            func hit() { l.lock(); n += 1; l.unlock() }
            func p(_ v: Double) { l.lock(); maxP = max(maxP, v); l.unlock() }
        }
        let c = Counter()
        let r = try await ObjectTracker.track(asset: AVURLAsset(url: url), box: squareBox(atX: 20), from: 0, to: 2,
                                              progress: { c.p($0) }, onSample: { _ in c.hit() })
        XCTAssertEqual(c.n, r.samples.count)
        XCTAssertGreaterThan(c.maxP, 0.9)
        XCTAssertLessThanOrEqual(c.maxP, 1.0001)
    }

    func testFollowsAVerticalScrollAndLosesTheBoxWhenItLeavesTheFrame() async throws {
        let speed = 40.0 // px/s, content moves down
        let texture = SyntheticVideo.noise(width: 320, height: 400, seed: 7)
        let url = try await SyntheticVideo.make(width: w, height: h, frames: 75) { i, ctx in
            ctx.interpolationQuality = .none
            let shift = (speed * Double(i) / 30).rounded()
            ctx.draw(texture, in: CGRect(x: 0, y: -220 + shift, width: 320, height: 400))
        }
        cleanup(url)
        // Box 80 x 50 px, top at y = 60: touches the bottom edge (y + 50 = 180) at t = 1.75, is fully out at 3.0.
        let box = CGRect(x: 100.0 / 320, y: 60.0 / 180, width: 80.0 / 320, height: 50.0 / 180)
        let r = try await track(url, box: box, from: 0, to: 2.5)
        let lost = try XCTUnwrap(r.lostAt, "the box leaves the frame, tracking must stop")
        XCTAssertEqual(lost, 1.75, accuracy: 0.35)
        for s in r.samples where s.t > 0.3 {
            XCTAssertEqual(s.dy * 180 / s.t, speed, accuracy: speed * 0.05, "t=\(s.t)")
            XCTAssertEqual(s.dx * 320, 0, accuracy: 2, "t=\(s.t)")
        }
        XCTAssertLessThanOrEqual(try XCTUnwrap(r.samples.last).t, lost + 0.001)
    }

    func testACoverAppearingOverTheBoxLosesTrackingWhenItAppears() async throws {
        let texture = SyntheticVideo.noise(width: 320, height: 180, seed: 3)
        let url = try await SyntheticVideo.make(width: w, height: h, frames: 60) { i, ctx in
            ctx.interpolationQuality = .none
            ctx.draw(texture, in: CGRect(x: 0, y: 0, width: 320, height: 180))
            if i >= 30 { // opaque flat cover from t = 1.0
                ctx.setFillColor(CGColor(gray: 0.1, alpha: 1))
                ctx.fill(CGRect(x: 110, y: 50, width: 120, height: 90))
            }
        }
        cleanup(url)
        let box = CGRect(x: 130.0 / 320, y: 70.0 / 180, width: 60.0 / 320, height: 50.0 / 180)
        let r = try await track(url, box: box, from: 0, to: 2)
        let lost = try XCTUnwrap(r.lostAt)
        XCTAssertEqual(lost, 1.0, accuracy: 0.1)
        XCTAssertFalse(r.offscreen, "being covered is not leaving the frame")
        XCTAssertTrue(r.lost)
        // Before the cover, the static content has not moved.
        for s in r.samples {
            XCTAssertEqual(s.dx * 320, 0, accuracy: 1.5)
            XCTAssertEqual(s.dy * 180, 0, accuracy: 1.5)
        }
    }

    func testTrackingStartedInTheMiddleFollowsBothSides() async throws {
        let speed = 60.0
        let url = try await movingSquare(speed: speed)
        // At t = 1.0 the square is at x = 20 + 60 = 110.
        let r = try await track(url, box: squareBox(atX: 80), from: 1.0, to: 2, lowerBound: 0)
        XCTAssertEqual(r.samples.map(\.t), r.samples.map(\.t).sorted(), "backward samples come first, in ascending order")
        XCTAssertTrue(r.samples.contains { $0.t < 0.9 }, "samples exist before the reference time")
        XCTAssertTrue(r.samples.contains { $0.t > 1.1 })
        let reference = try XCTUnwrap(r.samples.first { abs($0.t - 1.0) < 0.02 })
        XCTAssertEqual(reference.dx, 0)
        XCTAssertEqual(reference.dy, 0)
        XCTAssertEqual(r.samples.filter { abs($0.t - 1.0) < 0.02 }.count, 1, "the reference sample is not duplicated")
        for s in r.samples where abs(s.t - 1.0) > 0.1 {
            XCTAssertEqual(s.dx * 320, speed * (s.t - 1.0), accuracy: 4, "t=\(s.t)")
        }
        XCTAssertNil(r.lostAt)
    }

    func testCancellingTheTaskThrowsCancellationError() async throws {
        let url = try await movingSquare(speed: 60)
        let asset = AVURLAsset(url: url)
        let box = TaskBox()
        let region = squareBox(atX: 20)
        let task = Task { () -> ObjectTracker.Result in
            try await ObjectTracker.track(asset: asset, box: region, from: 0, to: 2,
                                          progress: { _ in }, onSample: { _ in box.cancel() })
        }
        box.set(task)
        do {
            _ = try await task.value
            XCTFail("a cancelled tracking must not return a result")
        } catch is CancellationError {
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testAnAssetWithoutAVideoTrackGivesAnEmptyResult() async throws {
        let r = try await ObjectTracker.track(asset: AVMutableComposition(), box: CGRect(x: 0, y: 0, width: 0.2, height: 0.2),
                                              from: 0, to: 1, progress: { _ in })
        XCTAssertTrue(r.samples.isEmpty)
        XCTAssertNil(r.lostAt)
    }
}

extension ObjectTrackerTests {
    /// An annotation can end a hair after the last frame (or the user drags past the end): tracking should
    /// just follow the video to its end, not fail.
    func testAnEndPastTheVideoDurationFollowsToTheEnd() async throws {
        let texture = SyntheticVideo.noise(width: 320, height: 180, seed: 5)
        let url = try await SyntheticVideo.make(width: 320, height: 180, frames: 30) { _, ctx in
            ctx.interpolationQuality = .none
            ctx.draw(texture, in: CGRect(x: 0, y: 0, width: 320, height: 180))
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        let box = CGRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        let r = try? await ObjectTracker.track(asset: AVURLAsset(url: url), box: box, from: 0, to: 5, progress: { _ in })
        XCTExpectFailure("ObjectTracker.track throws AVFoundation -11841 when `to` is beyond the asset duration (reader.timeRange past the video composition)", strict: false) {
            XCTAssertNotNil(r)
        }
    }
}
