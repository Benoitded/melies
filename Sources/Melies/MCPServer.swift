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

    // What the AI app is doing, for the Settings status and the badge in the editor.
    @Published private(set) var clientName: String?
    @Published private(set) var busyTool: String?
    @Published private(set) var lastTool: String?
    @Published private(set) var lastToolAt: Date?
    @Published private(set) var rejectedAt: Date?
    @Published private(set) var showBadge = false
    private var badgeTask: Task<Void, Never>?

    fileprivate func record(_ activity: MCPProtocol.Activity) {
        switch activity {
        case .client(let name): clientName = name
        case .started(let tool):
            busyTool = tool
            showBadge = true
            badgeTask?.cancel()
        case .finished(let tool, _):
            busyTool = nil
            lastTool = tool
            lastToolAt = Date()
            badgeTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(3.5))
                if !Task.isCancelled { self?.showBadge = false }
            }
        }
    }

    private var listener: NWListener?
    private lazy var recordingController: RecordingController = {
        let controller = RecordingController(
            layout: LiveScreenLayout(), confirmer: AlertConfirmer(), backend: LiveRecordingBackend(),
            isExportRunning: { EditorWindowController.shared.session.model?.busy ?? false },
            clientName: { [weak self] in self?.clientName })
        controller.onAutoStop = { outcome in Toast.show(L("mcprec.autostop", Int(outcome.duration))) }
        return controller
    }()

    private lazy var mcp: MCPProtocol = {
        var protocolHandler = MCPProtocol(tools: EditorTools(
            model: { EditorWindowController.shared.session.model },
            openVideo: { url in
                guard let target = url ?? LatestRecording.find() else { return nil }
                EditorWindowController.shared.open(target)
                return target
            },
            recording: recordingController
        ))
        protocolHandler.onActivity = { [weak self] activity in self?.record(activity) }
        return protocolHandler
    }()

    static var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: Pref.mcpEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: Pref.mcpEnabled) }
    }

    static var port: UInt16 {
        let saved = UserDefaults.standard.integer(forKey: Pref.mcpPort)
        return saved > 1023 && saved < 65536 ? UInt16(saved) : defaultPort
    }

    var url: String { "http://127.0.0.1:\(Self.port)/mcp" }

    /// For clients that only take a URL: the key rides in the address.
    var urlWithKey: String { "\(url)?token=\(token)" }

    /// The command that registers Melies in Claude Code.
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
                guard HTTPConnection.canAccept() else { connection.cancel(); return }
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
        clientName = nil; lastTool = nil; lastToolAt = nil; rejectedAt = nil
        token = Self.makeToken()
        TokenStore.write(token)
    }

    /// The key lives in the Keychain, not in the preferences file (readable by any program of the user, and copied
    /// into backups). A key left in the preferences by an older version is moved there.
    private static func loadToken() -> String {
        if let saved = TokenStore.read(), saved.count >= 32 { return saved }
        if let legacy = UserDefaults.standard.string(forKey: "mcpToken"), legacy.count >= 32 {
            // The old copy goes only once the Keychain really holds the key.
            if TokenStore.write(legacy) { UserDefaults.standard.removeObject(forKey: "mcpToken") }
            return legacy
        }
        let fresh = makeToken()
        TokenStore.write(fresh)
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
            // Exact host: a prefix test would accept http://localhost.evil.com.
            let originHost = URLComponents(string: origin)?.host?.lowercased()
            guard originHost == "127.0.0.1" || originHost == "localhost" else { return .status(403, "Forbidden") }
        }
        guard request.path == "/mcp" else { return .status(404, "Not Found") }
        guard authorized(request) else {
            rejectedAt = Date() // shown in Settings: an app is trying with an old key
            return .status(401, "Unauthorized")
        }
        switch request.method {
        case "POST":
            // One call at a time: two clients (or two calls) must not interleave their edits and undo steps.
            guard await acquire() else { return .status(499, "Client Closed Request") } // gone while waiting
            defer { release() }
            if Task.isCancelled { return .status(499, "Client Closed Request") }
            // A call that never ends (a tracking or export that hangs) must not block every later request:
            // after the deadline the long operations are cancelled so the call returns and the lock is released.
            let watchdog = Task { @MainActor in
                try? await Task.sleep(for: .seconds(Self.toolDeadline))
                guard !Task.isCancelled else { return }
                let model = EditorWindowController.shared.session.model
                model?.cancelTracking()
                model?.cancelExport()
            }
            defer { watchdog.cancel() }
            guard let reply = await mcp.handle(body: request.body) else { return .status(202, "Accepted") }
            return .json(reply)
        case "DELETE":
            return .status(200, "OK") // no sessions to close
        default:
            return .status(405, "Method Not Allowed")
        }
    }

    /// Seconds a single tool call may run before its long operations are cancelled.
    private static let toolDeadline = 120.0

    private var locked = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Bool, Never>)] = []

    /// True once the lock is held. False when the caller was cancelled (its client disconnected) while waiting: a
    /// dead connection must not run its mutating call later.
    private func acquire() async -> Bool {
        if !locked { locked = true; return true }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                if Task.isCancelled { continuation.resume(returning: false); return }
                waiters.append((id, continuation))
            }
        } onCancel: {
            Task { @MainActor in self.dropWaiter(id) }
        }
    }

    private func dropWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: false)
    }

    private func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().continuation.resume(returning: true) }
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

    /// JSON-RPC messages are small (a screenshot comes back, it does not go in): 1 MB is plenty.
    static let maxBody = 1024 * 1024

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
            let name = line[..<colon].lowercased()
            // Two Content-Length headers make the body length ambiguous: refuse instead of picking one.
            if name == "content-length", headers[name] != nil { return .some(nil) }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        // Chunked bodies are not supported; saying so is clearer than reading a length of zero.
        guard headers["transfer-encoding"] == nil else { return .some(nil) }
        guard let length = Int(headers["content-length"] ?? "0"), length >= 0, length <= Self.maxBody else { return .some(nil) }
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

    private static let lock = NSLock()
    nonisolated(unsafe) private static var active = 0
    private static let maxActive = 8

    /// False when too many connections are already open (a local client opening hundreds must not exhaust memory).
    static func canAccept() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return active < maxActive
    }

    init(_ connection: NWConnection, handler: @escaping @Sendable (HTTPRequest) async -> HTTPReply) {
        self.connection = connection
        self.handler = handler
        Self.lock.lock(); Self.active += 1; Self.lock.unlock()
    }

    deinit { Self.lock.lock(); Self.active -= 1; Self.lock.unlock() }

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
                let work = Task {
                    let reply = await handler(request)
                    send(reply)
                }
                Self.lock.lock(); self.work = work; Self.lock.unlock()
                watchPeer()
            case .some(.none):
                send(.status(400, "Bad Request"))
            case .none:
                if error != nil || finished { connection.cancel() } else { receive() }
            }
        }
    }

    private var work: Task<Void, Never>?

    /// Once the request is in, listens only for the client going away (EOF or error): the pending call is then
    /// cancelled, so it does not wait for a lock and run later for nobody.
    private func watchPeer() {
        connection.stateUpdateHandler = { [self] state in
            switch state {
            case .cancelled, .failed: cancelWork()
            default: break
            }
        }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [self] _, _, finished, error in
            if finished || error != nil { cancelWork() }
        }
    }

    private func cancelWork() {
        Self.lock.lock(); let work = self.work; Self.lock.unlock()
        work?.cancel()
    }

    private func send(_ reply: HTTPReply) {
        connection.send(content: reply.bytes, completion: .contentProcessed { [connection] _ in connection.cancel() })
    }
}

/// Keychain storage for the MCP key (a generic password, only readable while the Mac is unlocked, never synced).
private enum TokenStore {
    private static let service = "dev.melies.app.mcp-key"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "mcp"]
    }

    static func read() -> String? {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// True once the key is really in the Keychain (the caller keeps any older copy until then).
    @discardableResult
    static func write(_ token: String) -> Bool {
        let data = Data(token.utf8)
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
}
