import XCTest

/// A broken line in a .strings file makes macOS ignore the WHOLE file, and the app then shows raw keys everywhere
/// ("mm.file", "exp.nolimit"). This once slipped through, so the files are checked here.
final class LocalizationTests: XCTestCase {
    private var folder: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Localization")
    }

    private func table(_ language: String) throws -> [String: String] {
        let url = folder.appendingPathComponent("\(language).lproj/Localizable.strings")
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try XCTUnwrap(parsed as? [String: String], "\(language) is not a valid .strings file")
    }

    func testEveryLanguageFileParses() throws {
        for language in ["en", "fr", "it", "es"] { XCTAssertFalse(try table(language).isEmpty, language) }
    }

    func testEveryLanguageHasTheSameKeys() throws {
        let english = Set(try table("en").keys)
        for language in ["fr", "it", "es"] {
            let keys = Set(try table(language).keys)
            XCTAssertEqual(english.subtracting(keys).sorted(), [], "\(language) misses keys")
            XCTAssertEqual(keys.subtracting(english).sorted(), [], "\(language) has extra keys")
        }
    }

    func testFormatPlaceholdersMatchBetweenLanguages() throws {
        let english = try table("en")
        let pattern = try NSRegularExpression(pattern: "%(?:\\d+\\$)?[@dsf]|%\\.?\\d*[fd]")
        func placeholders(_ s: String) -> Int { pattern.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s)) }
        for language in ["fr", "it", "es"] {
            for (key, value) in try table(language) {
                XCTAssertEqual(placeholders(value), placeholders(english[key] ?? ""), "\(language) \(key): placeholders differ from English")
            }
        }
    }
}
