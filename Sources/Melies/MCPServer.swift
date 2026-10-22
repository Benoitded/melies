import Foundation
import Network
import Security

/// Optional local MCP server (off by default). Lets an AI client (Claude Code, Claude Desktop, Cursor...) drive
/// the editor with the tools of `EditorTools`. Only reachable from this Mac, and only with the token.
@MainActor
final class MCPServer: ObservableObject {
    static let shared = MCPServer()
    static let defaultPort: UInt16 = 47821

    @Published private(set) var running = false
    @Published private(set) var failure: String?
    @Published private(set) var token = MCPServer.loadToken()

    private var listener: NWListener?
    private lazy var mcp = MCPProtocol(tools: EditorTools(
        model: { EditorWindowController.shared.session.model },
        openVideo: { url in
            guard let target = url ?? LatestRecording.find() else { return nil }
            EditorWindowController.shared.open(target)
            return target
        }
    ))

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: "mcpEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "mcpEnabled") }
    }

    static var port: UInt16 {
        let saved = UserDefaults.standard.integer(forKey: "mcpPort")
        return saved > 1023 && saved < 65536 ? UInt16(saved) : defaultPort
    }

    var url: String { "http://127.0.0.1:\(Self.port)/mcp" }

    /// For clients that only take a URL: the key rides in the address.
    var urlWithKey: String { "\(url)?token=\(token)" }

    /// The command that registers Méliès in Claude Code.
    var claudeCodeCommand: String {
        "claude mcp add --transport http melies \(url) --header \"Authorization: Bearer \(token)\""
    }

    /// The same, for clients that take a JSON config.
    var jsonConfig: String {
        """
        {
          "mcpServers": {
            "melies": {
              "type": "http",
              "url": "\(url)",
              "headers": { "Authorization": "Bearer \(token)" }
            }
          }
        }
        """
    }

    /// Called at launch: starts only if the user turned it on.
    func startIfEnabled() {
        if Self.enabled { start() }
    }

    func setEnabled(_ on: Bool) {
        Self.enabled = on
        on ? start() : stop()
    }

    func start() {
        guard listener == nil else { return }
        failure = nil
        do {
            let parameters = NWParameters.tcp
            // Loopback only: nothing on the network can reach it.
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                HTTPConnection(connection) { request in
                    await self?.respond(to: request) ?? .status(503, "Unavailable")
                }.start()
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    guard let self else { return }
                    switch state {
                    case .ready: self.running = true
                    case .failed(let error):
                        self.failure = error.localizedDescription
                        self.stop(clearFailure: false)
                    default: break
                    }
                }
            }
            listener.start(queue: .global(qos: .userInitiated))
            self.listener = listener
        } catch {
            failure = error.localizedDescription
        }
    }

    func stop(clearFailure: Bool = true) {
        listener?.cancel()
        listener = nil
        running = false
        if clearFailure { failure = nil }
    }

    /// A new token: clients configured with the old one stop working.
    func regenerateToken() {
        token = Self.makeToken()
        UserDefaults.standard.set(token, forKey: "mcpToken")
    }

    private static func loadToken() -> String {
        if let saved = UserDefaults.standard.string(forKey: "mcpToken"), saved.count >= 32 { return saved }
        let fresh = makeToken()
        UserDefaults.standard.set(fresh, forKey: "mcpToken")
        return fresh
    }

    private static func makeToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return UUID().uuidString + UUID().uuidString }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Requests

    private func respond(to request: HTTPRequest) async -> HTTPReply {
        // A web page in the user's browser must not be able to reach this (DNS rebinding, CSRF).
        let host = request.header("host")?.lowercased().split(separator: ":").first.map(String.init) ?? ""
        guard host == "127.0.0.1" || host == "localhost" else { return .status(403, "Forbidden") }
        if let origin = request.header("origin") {
            let allowed = origin.hasPrefix("http://127.0.0.1") || origin.hasPrefix("http://localhost")
            guard allowed else { return .status(403, "Forbidden") }
        }
        guard request.path == "/mcp" else { return .status(404, "Not Found") }
        guard authorized(request) else { return .status(401, "Unauthorized") }
        switch request.method {
        case "POST":
            // One call at a time: two clients (or two calls) must not interleave their edits and undo steps.
            await acquire()
            defer { release() }
            guard let reply = await mcp.handle(body: request.body) else { return .status(202, "Accepted") }
            return .json(reply)
        case "DELETE":
            return .status(200, "OK") // no sessions to close
        default:
            return .status(405, "Method Not Allowed")
        }
    }

    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private func acquire() async {
        if locked { await withCheckedContinuation { waiters.append($0) } } else { locked = true }
    }

    private func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }

    private func authorized(_ request: HTTPRequest) -> Bool {
        let header = request.header("authorization") ?? ""
        let given = header.lowercased().hasPrefix("bearer ") ? String(header.dropFirst(7)) : (request.query["token"] ?? "")
        return Self.constantTimeEqual(given, token)
    }

    private static func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = x.count ^ y.count
        for i in 0..<min(x.count, y.count) { diff |= Int(x[i] ^ y[i]) }
        return diff == 0
    }
}

// MARK: HTTP

struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]
    let body: Data

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    /// Parses one request from the bytes received so far. nil means "need more bytes".
    static func parse(_ data: Data) -> HTTPRequest?? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return data.count > 64 * 1024 ? .some(nil) : nil }
        guard let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return .some(nil) }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return .some(nil) }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        guard length >= 0, length <= 40 * 1024 * 1024 else { return .some(nil) }
        let bodyStart = split.upperBound
        guard data.count - bodyStart >= length else { return nil }

        let target = String(start[1])
        let parts = target.split(separator: "?", maxSplits: 1).map(String.init)
        var query: [String: String] = [:]
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                query[kv[0]] = kv.count > 1 ? kv[1].removingPercentEncoding ?? kv[1] : ""
            }
        }
        return .some(HTTPRequest(method: String(start[0]).uppercased(), path: parts[0], query: query, headers: headers,
                                 body: data.subdata(in: bodyStart..<(bodyStart + length))))
    }
}

struct HTTPReply {
    let code: Int
    let reason: String
    let body: Data

    static func status(_ code: Int, _ reason: String) -> HTTPReply { HTTPReply(code: code, reason: reason, body: Data()) }
    static func json(_ body: Data) -> HTTPReply { HTTPReply(code: 200, reason: "OK", body: body) }

    var bytes: Data {
        var head = "HTTP/1.1 \(code) \(reason)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        if !body.isEmpty { head += "Content-Type: application/json\r\n" }
        if code == 405 { head += "Allow: POST\r\n" }
        if code == 401 { head += "WWW-Authenticate: Bearer\r\n" }
        return Data((head + "\r\n").utf8) + body
    }
}

/// One TCP connection, one request, one reply, then it closes.
final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let handler: @Sendable (HTTPRequest) async -> HTTPReply
    private var buffer = Data()

    init(_ connection: NWConnection, handler: @escaping @Sendable (HTTPRequest) async -> HTTPReply) {
        self.connection = connection
        self.handler = handler
    }

    private var idleTimeout: DispatchWorkItem?

    func start() {
        connection.start(queue: .global(qos: .userInitiated))
        // A client that connects and never finishes its request is dropped.
        let timeout = DispatchWorkItem { [connection] in connection.cancel() }
        idleTimeout = timeout
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeout)
        receive()
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [self] data, _, finished, error in
            if let data { buffer.append(data) }
            switch HTTPRequest.parse(buffer) {
            case .some(.some(let request)):
                idleTimeout?.cancel() // the request is complete; a long tool call is not idle
                Task {
                    let reply = await handler(request)
                    send(reply)
                }
            case .some(.none):
                send(.status(400, "Bad Request"))
            case .none:
                if error != nil || finished { connection.cancel() } else { receive() }
            }
        }
    }

    private func send(_ reply: HTTPReply) {
        connection.send(content: reply.bytes, completion: .contentProcessed { [connection] _ in connection.cancel() })
    }
}
