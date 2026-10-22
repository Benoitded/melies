import XCTest
@testable import Melies

@MainActor
final class SafetyTests: XCTestCase {
    // MARK: MCP export paths

    private let source = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("melies-test-source.mov")

    func testExportRefusesFoldersOutsideTheSafeOnes() {
        for path in ["/etc/passwd.mp4", "/usr/local/bin/x.mp4", "~/.ssh/key.mp4", "~/Library/Preferences/x.mp4", "/Applications/Melies.app/x.mp4"] {
            XCTAssertThrowsError(try EditorTools.safeExportTarget(path, ext: "mp4", source: source), path)
        }
    }

    func testExportFollowsSymlinkedStandardFolders() throws {
        let fm = FileManager.default
        let fakeHome = fm.temporaryDirectory.appendingPathComponent("melies-home-\(UUID().uuidString)")
        let real = fakeHome.appendingPathComponent("elsewhere/Films")
        try fm.createDirectory(at: real, withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: fakeHome.appendingPathComponent("Movies"), withDestinationURL: real)
        defer { try? fm.removeItem(at: fakeHome) }
        let url = try EditorTools.safeExportTarget(fakeHome.appendingPathComponent("Movies/a.mp4").path, ext: "mp4", source: URL(fileURLWithPath: "/nowhere/v.mov"), home: fakeHome.path)
        XCTAssertEqual(url.lastPathComponent, "a.mp4")
    }

    func testASourceInTheHomeFolderDoesNotOpenTheWholeHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let homeSource = home.appendingPathComponent("v.mov")
        XCTAssertThrowsError(try EditorTools.safeExportTarget(home.appendingPathComponent("Library/x.mp4").path, ext: "mp4", source: homeSource))
        XCTAssertThrowsError(try EditorTools.safeExportTarget("/x.mp4", ext: "mp4", source: URL(fileURLWithPath: "/v.mov")))
    }

    func testExportForcesTheExtension() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("melies-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = try EditorTools.safeExportTarget(folder.appendingPathComponent("notes.docx").path, ext: "mp4", source: source)
        XCTAssertEqual(url.pathExtension, "mp4")
        XCTAssertEqual(url.deletingPathExtension().lastPathComponent, "notes")
    }

    func testExportNeverPicksAnExistingFile() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("melies-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let existing = folder.appendingPathComponent("keep.mp4")
        try Data("precious".utf8).write(to: existing)
        let url = try EditorTools.safeExportTarget(existing.path, ext: "mp4", source: source)
        XCTAssertNotEqual(url.path, existing.path)
        XCTAssertEqual(url.lastPathComponent, "keep-2.mp4")
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "precious")
    }

    // MARK: HTTP parsing

    private func parse(_ text: String) -> HTTPRequest?? { HTTPRequest.parse(Data(text.utf8)) }

    func testAValidRequestIsParsed() throws {
        let body = "{}"
        let request = try XCTUnwrap(try XCTUnwrap(parse("POST /mcp?token=abc HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 2\r\n\r\n\(body)")))
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/mcp")
        XCTAssertEqual(request.query["token"], "abc")
        XCTAssertEqual(request.body, Data(body.utf8))
    }

    func testAnIncompleteRequestWaitsForMoreBytes() {
        XCTAssertNil(parse("POST /mcp HTTP/1.1\r\nContent-Length: 10\r\n\r\nabc"))
        XCTAssertNil(parse("POST /mcp HTTP/1.1\r\nHost: x"))
    }

    func testAmbiguousOrOversizedRequestsAreRefused() {
        // .some(nil) means "bad request".
        XCTAssertNotNil(parse("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 9\r\n\r\n{}"), "two lengths")
        if case .some(.none) = parse("POST /mcp HTTP/1.1\r\nContent-Length: 2\r\nContent-Length: 9\r\n\r\n{}") {} else { XCTFail("two Content-Length headers must be refused") }
        if case .some(.none) = parse("POST /mcp HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n") {} else { XCTFail("chunked must be refused") }
        if case .some(.none) = parse("POST /mcp HTTP/1.1\r\nContent-Length: \(HTTPRequest.maxBody + 1)\r\n\r\n") {} else { XCTFail("an oversized body must be refused") }
    }

    // MARK: Sidecar

    func testASidecarWithHugeOrBrokenValuesIsBoundedAndClamped() throws {
        let video = FileManager.default.temporaryDirectory.appendingPathComponent("melies-test-\(UUID().uuidString).mov")
        let sidecar = CursorTrack.sidecarURL(for: video)
        defer { try? FileManager.default.removeItem(at: sidecar) }
        let clicks = (0..<10_000).map { "[\($0).0, 5.0, -3.0]" }.joined(separator: ",")
        try Data("{\"cursor\":[[0,0.5,0.5]],\"clicks\":[\(clicks)]}".utf8).write(to: sidecar)
        let track = try XCTUnwrap(CursorTrack.load(for: video))
        XCTAssertLessThanOrEqual(track.clicks.count, 5_000)
        XCTAssertTrue(track.clicks.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }

    // MARK: Zoom camera

    func testNoZoomPointsMeansTheWholeFrame() {
        let state = ZoomCamera.state(at: 3, points: [])
        XCTAssertEqual(state.scale, 1, accuracy: 0.0001)
    }

    func testTheCameraNeverShowsOutsideTheFrame() {
        let c = ZoomCamera.clampedCenter(CGPoint(x: 0, y: 1), scale: 8)
        XCTAssertEqual(c.x, 0.0625, accuracy: 0.0001)
        XCTAssertEqual(c.y, 0.9375, accuracy: 0.0001)
    }
}

@MainActor
final class MCPProtocolTests: XCTestCase {
    private func makeProtocol() -> MCPProtocol {
        MCPProtocol(tools: EditorTools(model: { nil }, openVideo: { _ in nil }))
    }

    private func reply(_ json: String) async throws -> Any? {
        guard let data = await makeProtocol().handle(body: Data(json.utf8)) else { return nil }
        return try JSONSerialization.jsonObject(with: data)
    }

    func testAnEmptyBatchIsAnError() async throws {
        let r = try await reply("[]") as? [String: Any]
        XCTAssertEqual((r?["error"] as? [String: Any])?["code"] as? Int, -32600)
    }

    func testAClientResponseIsAcceptedWithoutAReply() async throws {
        let r = try await reply("{\"jsonrpc\":\"2.0\",\"id\":5,\"result\":{}}")
        XCTAssertNil(r)
    }

    func testABatchGivesOneErrorPerBadItem() async throws {
        let r = try await reply("[1,{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}]") as? [[String: Any]]
        XCTAssertEqual(r?.count, 2)
        XCTAssertNotNil(r?.first?["error"])
        XCTAssertNotNil(r?.last?["result"])
    }

    func testBrokenJSONIsAParseError() async throws {
        let r = try await reply("{not json") as? [String: Any]
        XCTAssertEqual((r?["error"] as? [String: Any])?["code"] as? Int, -32700)
    }

    func testAnUnknownMethodIsReported() async throws {
        let r = try await reply("{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"nope\"}") as? [String: Any]
        XCTAssertEqual((r?["error"] as? [String: Any])?["code"] as? Int, -32601)
    }
}
