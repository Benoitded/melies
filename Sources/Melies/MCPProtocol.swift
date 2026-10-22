import Foundation

/// The Model Context Protocol on top of `EditorTools`: JSON-RPC 2.0 messages in, messages out.
/// No networking here, so it can be driven from a test.
@MainActor
struct MCPProtocol {
    static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]

    let tools: EditorTools

    /// What the client is doing, so the app can show it (who connected, which tool is running).
    enum Activity { case client(String), started(String), finished(String, failed: Bool) }
    var onActivity: ((Activity) -> Void)?

    /// The reply to one JSON-RPC message, or nil when none is due (notifications).
    func handle(_ message: [String: Any]) async -> [String: Any]? {
        let id = message["id"]
        guard let method = message["method"] as? String else {
            // A response to a request we never sent (a client acknowledging something): accepted, no reply.
            if message["result"] != nil || message["error"] != nil { return nil }
            return id == nil ? nil : error(id, -32600, "Invalid request")
        }
        // Notifications have no id and get no reply.
        guard id != nil else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            if let name = (params["clientInfo"] as? [String: Any])?["name"] as? String { onActivity?(.client(name)) }
            let asked = params["protocolVersion"] as? String ?? ""
            return result(id, [
                "protocolVersion": Self.supportedVersions.contains(asked) ? asked : Self.supportedVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "melies", "version": Self.appVersion],
                "instructions": "Méliès is a video editor; you edit the video open in it. Call get_state first. All times are seconds of the SOURCE video (trimming does not shift them). Tool coordinates are 0...1 across the source frame, origin top left. Use get_frame to see the video, and get_frame with render true to check your edits as the export will show them. Every call can be undone with undo.",
            ])
        case "ping":
            return result(id, [:])
        case "tools/list":
            return result(id, ["tools": EditorTools.definitions.map {
                ["name": $0.name, "description": $0.description, "inputSchema": $0.schema]
            }])
        case "tools/call":
            guard let name = params["name"] as? String else { return error(id, -32602, "Missing tool name") }
            onActivity?(.started(name))
            let outcome = await call(name, params["arguments"] as? [String: Any] ?? [:])
            onActivity?(.finished(name, failed: outcome["isError"] as? Bool ?? false))
            return result(id, outcome)
        default:
            return error(id, -32601, "Method not found: \(method)")
        }
    }

    /// Handles a request body: one message or a batch. nil means "accepted, nothing to send back".
    func handle(body: Data) async -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: body) else {
            return encode(error(NSNull(), -32700, "Parse error"))
        }
        if let batch = object as? [Any] {
            guard !batch.isEmpty else { return encode(error(NSNull(), -32600, "Empty batch")) }
            var replies: [[String: Any]] = []
            for element in batch {
                guard let message = element as? [String: Any] else {
                    replies.append(error(NSNull(), -32600, "Invalid request")) // one error per bad item, not for the batch
                    continue
                }
                if let reply = await handle(message) { replies.append(reply) }
            }
            return replies.isEmpty ? nil : encode(replies)
        }
        guard let message = object as? [String: Any] else { return encode(error(NSNull(), -32600, "Invalid request")) }
        guard let reply = await handle(message) else { return nil }
        return encode(reply)
    }

    // MARK: Tool call

    /// A tool failure is a result with `isError`, so the model sees it and can adjust.
    private func call(_ name: String, _ arguments: [String: Any]) async -> [String: Any] {
        guard EditorTools.definitions.contains(where: { $0.name == name }) else {
            return ["content": [["type": "text", "text": "Unknown tool \(name)."]], "isError": true]
        }
        // One call is one undo step.
        let model = EditorWindowController.shared.session.model
        model?.beginUndoGroup()
        let (output, failed) = await tools.run(name, arguments)
        model?.endUndoGroup()

        var content: [[String: Any]] = [["type": "text", "text": output.text]]
        if let image = output.image {
            content.append(["type": "image", "data": image.base64EncodedString(), "mimeType": output.imageMIME])
        }
        return ["content": content, "isError": failed]
    }

    // MARK: JSON-RPC

    private func result(_ id: Any?, _ value: [String: Any]) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "result": value]
    }

    private func error(_ id: Any?, _ code: Int, _ message: String) -> [String: Any] {
        ["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message]]
    }

    private func encode(_ object: Any) -> Data? {
        try? JSONSerialization.data(withJSONObject: object)
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
