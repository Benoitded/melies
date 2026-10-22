import XCTest
@testable import Melies

final class CursorSmoothingTests: XCTestCase {
    private typealias S = CursorTrack.Sample

    /// A deterministic noisy diagonal path (no randomness).
    private func noisy(_ n: Int = 200) -> CursorTrack {
        CursorTrack(samples: (0..<n).map { i in
            let t = Double(i) / 60
            let base = Double(i) / Double(n - 1)
            let jitter = (i % 2 == 0 ? 1 : -1) * 0.01 * Double((i * 7) % 5 + 1) / 5
            return S(t: t, x: base * 0.8 + 0.1 + jitter, y: base * 0.5 + 0.2 - jitter)
        })
    }

    private func pathLength(_ track: CursorTrack) -> Double {
        zip(track.samples, track.samples.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    func testOffIsIdentity() {
        let t = noisy()
        XCTAssertEqual(t.smoothed(strength: .off).samples.map(\.x), t.samples.map(\.x))
    }

    func testKeepsEndpoints() {
        let t = noisy()
        for level in [CursorSmoothing.light, .smooth] {
            let s = t.smoothed(strength: level).samples
            XCTAssertEqual(s.first?.x, t.samples.first?.x)
            XCTAssertEqual(s.last?.y, t.samples.last?.y)
            XCTAssertEqual(s.count, t.samples.count)
        }
    }

    func testReducesJitterAndIsMonotonicInStrength() {
        let t = noisy()
        let raw = pathLength(t), light = pathLength(t.smoothed(strength: .light)), smooth = pathLength(t.smoothed(strength: .smooth))
        XCTAssertLessThan(light, raw)
        XCTAssertLessThan(smooth, light)
    }

    func testTinyAndBrokenInputsDoNotCrash() {
        for level in CursorSmoothing.allCases {
            XCTAssertTrue(CursorTrack(samples: []).smoothed(strength: level).samples.isEmpty)
            XCTAssertEqual(CursorTrack(samples: [S(t: 0, x: 0.3, y: 0.3)]).smoothed(strength: level).samples.count, 1)
            XCTAssertEqual(CursorTrack(samples: [S(t: 0, x: 0.3, y: 0.3), S(t: 1, x: 0.6, y: 0.6)]).smoothed(strength: level).samples.count, 2)
        }
    }

    func testUnsortedAndDuplicateTimestamps() {
        let t = CursorTrack(samples: [S(t: 2, x: 0.9, y: 0.9), S(t: 0, x: 0.1, y: 0.1), S(t: 1, x: 0.5, y: 0.5),
                                      S(t: 1, x: 0.6, y: 0.4), S(t: 1, x: 0.5, y: 0.5)])
        let s = t.smoothed(strength: .smooth).samples
        XCTAssertEqual(s.map(\.t), [0, 1, 1, 1, 2])
        XCTAssertEqual(s.first?.x, 0.1)
        XCTAssertEqual(s.last?.x, 0.9)
        XCTAssertTrue(s.allSatisfy { $0.x.isFinite && $0.y.isFinite })
    }

    func testSavedDefaultsToLight() {
        UserDefaults.standard.removeObject(forKey: Pref.cursorSmoothing)
        XCTAssertEqual(CursorSmoothing.saved, .light)
    }
}
