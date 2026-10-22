import AVFoundation
import XCTest
@testable import Melies

/// The speech engine is never involved: recognized words are injected as plain values.
final class CaptionTests: XCTestCase {
    private func words(_ text: String, from start: Double = 0, step: Double = 0.4) -> [CaptionWord] {
        text.split(separator: " ").enumerated().map { i, w in
            CaptionWord(text: String(w), start: start + Double(i) * step, end: start + Double(i) * step + step * 0.9)
        }
    }

    func testShortSentenceIsOneCaption() {
        let captions = CaptionLayout.group(words("Hello and welcome"))
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(captions[0].text, "Hello and welcome")
        XCTAssertEqual(captions[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(captions[0].end, 1.16, accuracy: 0.001)
    }

    func testLongTextSplitsAtTwoLinesOf42() {
        let text = (1...40).map { _ in "word" }.joined(separator: " ")
        let captions = CaptionLayout.group(words(text, step: 0.2))
        XCTAssertGreaterThan(captions.count, 1)
        for c in captions {
            let lines = CaptionLayout.wrap(c.text)
            XCTAssertLessThanOrEqual(lines.count, 2)
            XCTAssertTrue(lines.allSatisfy { $0.count <= 42 })
        }
        XCTAssertEqual(captions.map(\.text).joined(separator: " "), text)
    }

    func testPauseSplits() {
        let all = words("first part") + words("second part", from: 5)
        let captions = CaptionLayout.group(all)
        XCTAssertEqual(captions.map(\.text), ["first part", "second part"])
    }

    func testMaxDurationSplits() {
        let captions = CaptionLayout.group(words("a b c d e f g h i j", step: 1.5))
        XCTAssertGreaterThan(captions.count, 1)
        XCTAssertTrue(captions.allSatisfy { $0.end - $0.start <= 6.0 + 0.001 })
    }

    func testSentenceEndSplitsOnceLineHasLength() {
        let all = words("This is a first complete sentence. And a second one") // 34 chars before the period
        let captions = CaptionLayout.group(all)
        XCTAssertEqual(captions.map(\.text), ["This is a first complete sentence.", "And a second one"])
    }

    func testEmptyAndBlankWordsGiveNothing() {
        XCTAssertTrue(CaptionLayout.group([]).isEmpty)
        XCTAssertTrue(CaptionLayout.group([CaptionWord(text: "  ", start: 0, end: 1)]).isEmpty)
    }

    func testCaptionsNeverOverlapAndHaveMinimumDuration() {
        let all = [CaptionWord(text: "Hi.", start: 0, end: 0.05), CaptionWord(text: "There", start: 0.1, end: 0.5)]
        let captions = CaptionLayout.group(all, maxChars: 3)
        XCTAssertEqual(captions.count, 2)
        XCTAssertLessThanOrEqual(captions[0].end, captions[1].start)
    }

    func testWrapKeepsLongWordAlone() {
        let long = String(repeating: "x", count: 60)
        XCTAssertEqual(CaptionLayout.wrap("a \(long) b"), ["a", long, "b"])
    }

    func testWordsFromPieceShareTimeByLength() {
        let w = CaptionLayout.words(from: "ab cdef", start: 1, end: 4)
        XCTAssertEqual(w.map(\.text), ["ab", "cdef"])
        XCTAssertEqual(w[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(w[0].end, 2, accuracy: 0.001)
        XCTAssertEqual(w[1].end, 4, accuracy: 0.001)
        XCTAssertTrue(CaptionLayout.words(from: "   ", start: 0, end: 1).isEmpty)
    }

    // MARK: Trim

    func testClampCutsAndDrops() {
        let list = [Caption(start: 0, end: 2, text: "a"), Caption(start: 3, end: 6, text: "b"), Caption(start: 8, end: 9, text: "c")]
        let clamped = CaptionLayout.clamp(list, start: 1, end: 5)
        XCTAssertEqual(clamped.map(\.text), ["a", "b"])
        XCTAssertEqual(clamped[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(clamped[1].end, 5, accuracy: 0.001)
    }

    func testClampDropsTinySlivers() {
        let list = [Caption(start: 0, end: 1.05, text: "a")]
        XCTAssertTrue(CaptionLayout.clamp(list, start: 1, end: 5).isEmpty)
    }

    func testTrimShiftsToZero() {
        let list = [Caption(start: 3, end: 6, text: "b")]
        let kept = CaptionLayout.forTrim(list, start: 2, end: 5)
        XCTAssertEqual(kept[0].start, 1, accuracy: 0.001)
        XCTAssertEqual(kept[0].end, 3, accuracy: 0.001)
    }

    func testShiftNeverGoesNegative() {
        let shifted = CaptionLayout.shifted([Caption(start: 1, end: 3, text: "a")], by: 2)
        XCTAssertEqual(shifted[0].start, 0)
        XCTAssertEqual(shifted[0].end, 1, accuracy: 0.001)
    }

    func testVisibleAt() {
        let list = [Caption(start: 1, end: 2, text: "a"), Caption(start: 3, end: 4, text: "b")]
        XCTAssertEqual(CaptionLayout.visible(list, at: 1.5)?.text, "a")
        XCTAssertNil(CaptionLayout.visible(list, at: 2.5))
        XCTAssertNil(CaptionLayout.visible([], at: 0))
    }

    // MARK: SRT

    func testSRTTimecode() {
        XCTAssertEqual(CaptionLayout.srtTimecode(1.25), "00:00:01,250")
        XCTAssertEqual(CaptionLayout.srtTimecode(0), "00:00:00,000")
        XCTAssertEqual(CaptionLayout.srtTimecode(3725.5), "01:02:05,500")
        XCTAssertEqual(CaptionLayout.srtTimecode(-4), "00:00:00,000")
        XCTAssertEqual(CaptionLayout.srtTimecode(59.9996), "00:01:00,000")
    }

    func testSRTFile() {
        let list = [Caption(start: 1.25, end: 2.5, text: "Hello"), Caption(start: 3, end: 4, text: "World")]
        XCTAssertEqual(CaptionLayout.srt(list), "1\n00:00:01,250 --> 00:00:02,500\nHello\n\n2\n00:00:03,000 --> 00:00:04,000\nWorld\n")
        XCTAssertEqual(CaptionLayout.srt([]), "")
    }

    func testSRTWrapsLongLines() {
        let text = "this caption is quite long and goes over forty two characters"
        let out = CaptionLayout.srt([Caption(start: 0, end: 1, text: text)])
        XCTAssertEqual(out.split(separator: "\n").count, 4) // index, time, two text lines
    }

    // MARK: Errors and engine-free behaviour

    func testErrorsHaveMessages() {
        for e in [CaptionError.noAudio, .permissionDenied, .unsupported, .languageUnavailable, .noSpeech, .failed] {
            XCTAssertFalse(e.errorDescription?.isEmpty ?? true)
        }
    }

    func testDefaultLocalePrefersAppLanguage() {
        let installed = [Locale(identifier: "en_US"), Locale(identifier: "fr_FR")]
        XCTAssertEqual(CaptionGenerator.defaultLocale(among: installed, preferred: ["fr"])?.identifier, "fr_FR")
        XCTAssertEqual(CaptionGenerator.defaultLocale(among: installed, preferred: ["de", "en"])?.identifier, "en_US")
        XCTAssertEqual(CaptionGenerator.defaultLocale(among: installed, preferred: ["ja"])?.identifier, "en_US")
        XCTAssertNil(CaptionGenerator.defaultLocale(among: [], preferred: ["fr"]))
    }

    func testVideoWithoutAudioReportsNoAudio() async throws {
        let url = try await SyntheticVideo.make(width: 64, height: 64, frames: 5) { _, _ in }
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            _ = try await CaptionGenerator.generate(asset: AVURLAsset(url: url), locale: Locale(identifier: "en_US")) { _ in }
            XCTFail("expected noAudio")
        } catch {
            XCTAssertEqual(error as? CaptionError, .noAudio)
        }
    }

    func testRenderPlanDrawsCaptionOnlyWhenVisible() {
        let plan = CaptionPlan(captions: [Caption(start: 1, end: 2, text: "Hi")], style: CaptionStyle())
        let content = CGRect(x: 0, y: 0, width: 320, height: 180)
        XCTAssertNotNil(CaptionRenderer.overlay(plan, at: 1.5, content: content, canvas: content.size))
        XCTAssertNil(CaptionRenderer.overlay(plan, at: 3, content: content, canvas: content.size))
    }
}
