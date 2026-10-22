import XCTest
@testable import Melies

@MainActor
final class EditorToolsValidationTests: XCTestCase {
    private func message(_ body: () throws -> Any?) -> String? {
        do { _ = try body(); return nil } catch { return (error as? ToolError)?.message ?? "not a ToolError: \(error)" }
    }

    // MARK: number / optional

    func testANumberIsReadAsADouble() throws {
        XCTAssertEqual(try EditorTools.number(["t": 2.5], "t", in: 0...10), 2.5)
        XCTAssertEqual(try EditorTools.number(["t": 3], "t", in: 0...10), 3)
        XCTAssertEqual(try EditorTools.number(["t": NSNumber(value: 4)], "t", in: 0...10), 4)
        XCTAssertEqual(try EditorTools.number(["t": 0], "t", in: 0...10), 0, "0 is a number, not a Bool")
        XCTAssertEqual(try EditorTools.number(["t": 1], "t", in: 0...10), 1, "1 is a number, not a Bool")
    }

    func testBoundsAreInclusive() throws {
        XCTAssertEqual(try EditorTools.number(["t": 0], "t", in: 0...8), 0)
        XCTAssertEqual(try EditorTools.number(["t": 8], "t", in: 0...8), 8)
    }

    func testABooleanIsNotANumber() {
        for value in [true, false] {
            XCTAssertEqual(message { try EditorTools.number(["t": value], "t", in: 0...10) }, "t must be a number.")
        }
        // What JSONSerialization produces for true / false.
        let parsed = try? JSONSerialization.jsonObject(with: Data(#"{"a":true,"b":false,"c":1,"d":0}"#.utf8)) as? [String: Any]
        XCTAssertEqual(message { try EditorTools.number(parsed ?? [:], "a", in: 0...10) }, "a must be a number.")
        XCTAssertEqual(message { try EditorTools.number(parsed ?? [:], "b", in: 0...10) }, "b must be a number.")
        XCTAssertEqual(try EditorTools.number(parsed ?? [:], "c", in: 0...10), 1)
        XCTAssertEqual(try EditorTools.number(parsed ?? [:], "d", in: 0...10), 0)
    }

    func testNaNAndInfinityAreRefused() {
        for v in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(message { try EditorTools.number(["t": v], "t", in: 0...10) }, "t must be a number.", "\(v)")
        }
    }

    func testOtherTypesAreRefused() {
        for v: Any in ["3", "", [1], ["a": 1], Date()] {
            XCTAssertEqual(message { try EditorTools.number(["t": v], "t", in: 0...10) }, "t must be a number.", "\(v)")
        }
    }

    func testAMissingOrNullNumberIsRequired() {
        XCTAssertEqual(message { try EditorTools.number([:], "start", in: 0...10) }, "start is required.")
        XCTAssertEqual(message { try EditorTools.number(["start": NSNull()], "start", in: 0...10) }, "start is required.")
    }

    func testAnOptionalNumberMayBeMissingOrNull() throws {
        XCTAssertNil(try EditorTools.optional([:], "x", in: 0...1))
        XCTAssertNil(try EditorTools.optional(["x": NSNull()], "x", in: 0...1))
        XCTAssertEqual(try EditorTools.optional(["x": 0.25], "x", in: 0...1), 0.25)
    }

    func testAnOptionalNumberIsStillValidatedWhenGiven() {
        XCTAssertEqual(message { try EditorTools.optional(["x": true], "x", in: 0...1) }, "x must be a number.")
        XCTAssertEqual(message { try EditorTools.optional(["x": Double.nan], "x", in: 0...1) }, "x must be a number.")
        XCTAssertNotNil(message { try EditorTools.optional(["x": 1.5], "x", in: 0...1) })
    }

    func testOutOfRangeSaysWhichArgumentAndWhatWasExpected() throws {
        let tooBig = try XCTUnwrap(message { try EditorTools.number(["scale": 9], "scale", in: 1...8) })
        XCTAssertTrue(tooBig.hasPrefix("scale must be between"), tooBig)
        XCTAssertTrue(tooBig.contains("1") && tooBig.contains("8") && tooBig.contains("got 9"), tooBig)
        let tooSmall = try XCTUnwrap(message { try EditorTools.number(["time": -0.5], "time", in: 0...12) })
        XCTAssertTrue(tooSmall.contains("time") && tooSmall.contains("12") && tooSmall.contains("got -0.5"), tooSmall)
        XCTAssertNotNil(message { try EditorTools.number(["t": Double.greatestFiniteMagnitude], "t", in: 0...10) })
    }

    // MARK: colors

    func testNamedColors() throws {
        XCTAssertEqual(try EditorTools.color("red"), .red)
        XCTAssertEqual(try EditorTools.color("orange"), .orange)
        XCTAssertEqual(try EditorTools.color("yellow"), .yellow)
        XCTAssertEqual(try EditorTools.color("green"), .green)
        XCTAssertEqual(try EditorTools.color("blue"), .blue)
        XCTAssertEqual(try EditorTools.color("purple"), .purple)
        XCTAssertEqual(try EditorTools.color("white"), .white)
        XCTAssertEqual(try EditorTools.color("black"), .black)
        XCTAssertEqual(try EditorTools.color("  RED "), .red, "case and surrounding spaces do not matter")
        XCTAssertEqual(try EditorTools.color("Blue"), .blue)
    }

    func testHexColors() throws {
        XCTAssertEqual(try EditorTools.color("#FF0000"), RGBA(r: 1, g: 0, b: 0, a: 1))
        XCTAssertEqual(try EditorTools.color("#00ff80"), RGBA(r: 0, g: 1, b: 128.0 / 255, a: 1))
        XCTAssertEqual(try EditorTools.color("1A2B3C"), RGBA(r: 26.0 / 255, g: 43.0 / 255, b: 60.0 / 255, a: 1), "the # is optional")
        XCTAssertEqual(try EditorTools.color("#000000"), RGBA(r: 0, g: 0, b: 0, a: 1))
        XCTAssertEqual(try EditorTools.color("#FFFFFF").a, 1)
    }

    func testBadColorsGiveAClearMessage() throws {
        for bad in ["", "#", "#FFF", "#12345", "#1234567", "#GGGGGG", "ZZZZZZ", "pink", "red blue", "#FF 000", "rgb(1,2,3)", "#FF00FF00", "néon", "#-12345"] {
            let m = try XCTUnwrap(message { try EditorTools.color(bad) }, "\(bad) must be refused")
            XCTAssertTrue(m.contains("#RRGGBB") && m.contains("red"), "\(bad): \(m)")
        }
    }

    /// `UInt32("+12345", radix: 16)` accepts a sign, so "#+12345" slips through as the colour #012345.
    func testASignInsideAHexColorIsRefused() {
        XCTExpectFailure("EditorTools.color accepts a leading '+' because UInt32(_, radix:) parses signs (EditorTools.swift, color)") {
            XCTAssertNotNil(message { try EditorTools.color("#+12345") })
        }
    }

    func testHexRoundTripsAndNamesComeBack() throws {
        XCTAssertEqual(EditorTools.hex(.red), "red")
        XCTAssertEqual(EditorTools.hex(.black), "black")
        XCTAssertEqual(EditorTools.hex(RGBA(r: 26.0 / 255, g: 43.0 / 255, b: 60.0 / 255, a: 1)), "#1A2B3C")
        XCTAssertEqual(try EditorTools.color(EditorTools.hex(try EditorTools.color("#1A2B3C"))), try EditorTools.color("#1A2B3C"))
        for c in RGBA.palette { XCTAssertEqual(try EditorTools.color(EditorTools.hex(c)), c) }
        XCTAssertEqual(EditorTools.hex(RGBA(r: 2, g: -1, b: 0.5, a: 1)), "#FF0080", "out of range components are clamped")
    }

    // MARK: tool definitions

    func testEveryDefinitionHasAUniqueNameAndAConsistentSchema() throws {
        let names = EditorTools.definitions.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicate tool names")
        for tool in EditorTools.definitions {
            XCTAssertFalse(tool.description.isEmpty, tool.name)
            XCTAssertEqual(tool.schema["type"] as? String, "object", tool.name)
            let props = try XCTUnwrap(tool.schema["properties"] as? [String: Any], tool.name)
            for key in tool.schema["required"] as? [String] ?? [] {
                XCTAssertNotNil(props[key], "\(tool.name): required \(key) is not a property")
            }
            XCTAssertTrue(JSONSerialization.isValidJSONObject(tool.schema), "\(tool.name): schema must be JSON")
        }
    }

    // MARK: tool errors do not crash

    private func nothingOpen() -> EditorTools { EditorTools(model: { nil }, openVideo: { _ in nil }) }

    func testEveryToolFailsWithAMessageWhenNoVideoIsOpen() async {
        let tools = nothingOpen()
        for tool in EditorTools.definitions where tool.name != "open_video" {
            let r = await tools.run(tool.name, [:])
            XCTAssertTrue(r.failed, tool.name)
            XCTAssertTrue(r.output.text.contains("open_video"), "\(tool.name): \(r.output.text)")
        }
    }

    func testGarbageArgumentsNeverCrash() async {
        let tools = nothingOpen()
        let garbage: [[String: Any]] = [
            ["time": Double.nan], ["time": true], ["time": NSNull()], ["time": "abc"], ["id": 12], ["id": "not-a-uuid"],
            ["path": 5], ["x": Double.infinity, "y": -Double.infinity], ["start": [1, 2], "end": ["a": 1]], ["kind": NSNull()],
            ["text": String(repeating: "é", count: 10_000)], ["color": "#ZZZZZZ"],
        ]
        for tool in EditorTools.definitions {
            for args in garbage {
                let r = await tools.run(tool.name, args)
                XCTAssertFalse(r.output.text.isEmpty, "\(tool.name) \(args)")
            }
        }
    }

    func testAnUnknownToolIsReported() async {
        let r = await nothingOpen().run("rm_rf", [:])
        XCTAssertTrue(r.failed)
        XCTAssertFalse(r.output.text.isEmpty)
    }

    func testOpeningAMissingFileOrAWrongTypeIsRefusedWithAReason() async throws {
        let tools = nothingOpen()
        let missing = await tools.run("open_video", ["path": "/definitely/not/here.mov"])
        XCTAssertTrue(missing.failed)
        XCTAssertTrue(missing.output.text.contains("No file at"), missing.output.text)

        let text = FileManager.default.temporaryDirectory.appendingPathComponent("melies-test-\(UUID().uuidString).txt")
        try Data("hello".utf8).write(to: text)
        addTeardownBlock { try? FileManager.default.removeItem(at: text) }
        let wrong = await tools.run("open_video", ["path": text.path])
        XCTAssertTrue(wrong.failed)
        XCTAssertTrue(wrong.output.text.contains(".mov"), wrong.output.text)

        let movie = FileManager.default.temporaryDirectory.appendingPathComponent("melies-test-\(UUID().uuidString).mov")
        try Data("x".utf8).write(to: movie)
        addTeardownBlock { try? FileManager.default.removeItem(at: movie) }
        let refused = await tools.run("open_video", ["path": movie.path]) // the opener returns nil
        XCTAssertTrue(refused.failed)
        XCTAssertTrue(refused.output.text.contains("Could not open"), refused.output.text)
    }

    func testToolErrorCarriesItsMessage() {
        let e = ToolError("bad")
        XCTAssertEqual(e.localizedDescription, "bad")
        XCTAssertEqual(e.message, "bad")
    }
}
