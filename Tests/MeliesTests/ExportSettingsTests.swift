import XCTest
@testable import Melies

final class ExportSettingsTests: XCTestCase {
    private let hd = CGSize(width: 1920, height: 1080)

    private func settings(mb: Int? = nil, format: ExportSettings.Format = .mp4) -> ExportSettings {
        ExportSettings(format: format, maxMegabytes: mb, maxWidth: 1920)
    }

    func testChoicesAreAscendingAndUnique() {
        XCTAssertEqual(ExportSettings.sizeChoices, ExportSettings.sizeChoices.sorted())
        XCTAssertEqual(Set(ExportSettings.sizeChoices).count, ExportSettings.sizeChoices.count)
        XCTAssertEqual(ExportSettings.widthChoices, ExportSettings.widthChoices.sorted())
        XCTAssertTrue(ExportSettings.widthChoices.contains(ExportSettings().maxWidth), "the default width is one of the choices")
    }

    func testTheSizeLimitSetsTheBitrateFromTheFileBudget() {
        // 5 MB over 10 s: 5e6 * 8 * 0.93 / 10 = 3.72 Mbit/s
        XCTAssertEqual(settings(mb: 5).videoBitrate(seconds: 10, canvas: hd, hasAudio: false), 3_720_000)
    }

    func testAudioReservesItsShareOfTheBudget() {
        let without = settings(mb: 5).videoBitrate(seconds: 10, canvas: hd, hasAudio: false)
        let with = settings(mb: 5).videoBitrate(seconds: 10, canvas: hd, hasAudio: true)
        XCTAssertEqual(without - with, 128_000, "128 kbit/s of audio are taken off the video")
    }

    func testBitrateGrowsWithTheSizeLimit() {
        let rates = ExportSettings.sizeChoices.map { settings(mb: $0).videoBitrate(seconds: 20, canvas: hd, hasAudio: true) }
        XCTAssertEqual(rates, rates.sorted())
        XCTAssertGreaterThan(rates.last!, rates.first!)
    }

    func testBitrateShrinksWithTheDuration() {
        let rates = [5.0, 10, 30, 60, 120, 600].map { settings(mb: 8).videoBitrate(seconds: $0, canvas: hd, hasAudio: false) }
        XCTAssertEqual(rates, rates.sorted(by: >))
        XCTAssertGreaterThan(rates.first!, rates.last!)
    }

    func testTheSizeLimitBitrateIsClamped() {
        XCTAssertEqual(settings(mb: 1).videoBitrate(seconds: 3600, canvas: hd, hasAudio: true), 120_000, "never below 120 kbit/s")
        XCTAssertEqual(settings(mb: 100).videoBitrate(seconds: 1, canvas: hd, hasAudio: false), 20_000_000, "never above 20 Mbit/s")
    }

    func testAnAudioBudgetBiggerThanTheFileDoesNotGoNegative() {
        // 1 MB over 600 s: the audio alone (76.8 Mbit) is far more than the 7.44 Mbit of the budget
        XCTAssertEqual(settings(mb: 1).videoBitrate(seconds: 600, canvas: hd, hasAudio: true), 120_000)
    }

    func testAZeroOrNegativeDurationIsTreatedAsOneTenthOfASecond() {
        let tiny = settings(mb: 1).videoBitrate(seconds: 0.1, canvas: hd, hasAudio: false)
        XCTAssertEqual(settings(mb: 1).videoBitrate(seconds: 0, canvas: hd, hasAudio: false), tiny)
        XCTAssertEqual(settings(mb: 1).videoBitrate(seconds: -5, canvas: hd, hasAudio: false), tiny)
        XCTAssertGreaterThan(tiny, 0)
    }

    func testTheSizeLimitIgnoresTheCanvasAndTheCodec() {
        let a = settings(mb: 8).videoBitrate(seconds: 20, canvas: hd, hasAudio: true)
        XCTAssertEqual(settings(mb: 8).videoBitrate(seconds: 20, canvas: CGSize(width: 640, height: 360), hasAudio: true), a)
        XCTAssertEqual(settings(mb: 8, format: .hevc).videoBitrate(seconds: 20, canvas: hd, hasAudio: true), a)
    }

    func testWithoutALimitTheBitrateFollowsThePixelCount() {
        // 1920 x 1080 x 30 x 0.1 = 6.2208 Mbit/s
        XCTAssertEqual(settings().videoBitrate(seconds: 10, canvas: hd, hasAudio: true), 6_220_800)
        let small = settings().videoBitrate(seconds: 10, canvas: CGSize(width: 1280, height: 720), hasAudio: true)
        XCTAssertEqual(small, 2_764_800)
        XCTAssertLessThan(small, 6_220_800)
    }

    func testWithoutALimitHEVCNeedsFortyPercentFewerBits() {
        let h264 = settings().videoBitrate(seconds: 10, canvas: hd, hasAudio: false)
        let hevc = settings(format: .hevc).videoBitrate(seconds: 10, canvas: hd, hasAudio: false)
        XCTAssertEqual(Double(hevc) / Double(h264), 0.6, accuracy: 0.001)
    }

    func testWithoutALimitTheBitrateIsClamped() {
        let tiny = CGSize(width: 100, height: 100)
        let huge = CGSize(width: 8192, height: 4320)
        XCTAssertEqual(settings().videoBitrate(seconds: 10, canvas: tiny, hasAudio: false), 1_500_000)
        XCTAssertEqual(settings(format: .hevc).videoBitrate(seconds: 10, canvas: tiny, hasAudio: false), 900_000, "the floor scales with the codec factor")
        XCTAssertEqual(settings().videoBitrate(seconds: 10, canvas: huge, hasAudio: false), 16_000_000)
        XCTAssertEqual(settings(format: .hevc).videoBitrate(seconds: 10, canvas: huge, hasAudio: false), 16_000_000)
    }

    func testWithoutALimitTheDurationDoesNotMatter() {
        XCTAssertEqual(settings().videoBitrate(seconds: 1, canvas: hd, hasAudio: true), settings().videoBitrate(seconds: 900, canvas: hd, hasAudio: false))
    }

    func testFormatsMapToFileTypes() {
        XCTAssertEqual(settings().fileExtension, "mp4")
        XCTAssertEqual(settings(format: .hevc).fileExtension, "mp4")
        XCTAssertEqual(ExportSettings(format: .gif).fileExtension, "gif")
        XCTAssertTrue(ExportSettings.Format.mp4.isVideo)
        XCTAssertTrue(ExportSettings.Format.hevc.isVideo)
        XCTAssertFalse(ExportSettings.Format.gif.isVideo)
        XCTAssertEqual(ExportSettings.Format(rawValue: "hevc"), .hevc)
        XCTAssertNil(ExportSettings.Format(rawValue: "avi"))
    }

    func testTheExportControlClampsProgressAndRemembersCancellation() {
        final class Last: @unchecked Sendable { var v = -1.0 }
        let last = Last()
        let control = ExportControl { last.v = $0 }
        control.report(-3); XCTAssertEqual(last.v, 0)
        control.report(0.4); XCTAssertEqual(last.v, 0.4)
        control.report(7); XCTAssertEqual(last.v, 1)
        XCTAssertFalse(control.isCancelled)
        control.cancel()
        XCTAssertTrue(control.isCancelled)
    }
}
