import AVFoundation
import AppKit

/// A tool an AI can call: a name, what it does, and a JSON schema of its arguments.
struct ToolDefinition {
    let name: String
    let description: String
    let schema: [String: Any]
}

/// What a tool returns: text for the model, and sometimes an image (a video frame).
struct ToolOutput {
    var text: String
    var image: Data?
    var imageMIME = "image/jpeg"
}

/// A problem the model can read and fix (bad argument, nothing open). Never a crash.
struct ToolError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// The editor as a set of tools with JSON arguments. It knows neither MCP nor any AI provider:
/// both sit on top of `definitions` and `call`.
/// Times are seconds of the source video. Coordinates are normalized 0...1 in the upright source frame,
/// origin top left, like `Annotation` and `ZoomPoint`.
@MainActor
final class EditorTools {
    private let currentModel: () -> EditorModel?

    init(model: @escaping () -> EditorModel?) { currentModel = model }

    convenience init(session: EditorSession) { self.init(model: { [weak session] in session?.model }) }

    // MARK: Definitions

    nonisolated static let definitions: [ToolDefinition] = {
        func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] {
            ["type": "object", "properties": props, "required": required]
        }
        func num(_ doc: String) -> [String: Any] { ["type": "number", "description": doc] }
        func str(_ doc: String, _ options: [String]? = nil) -> [String: Any] {
            var d: [String: Any] = ["type": "string", "description": doc]
            if let options { d["enum"] = options }
            return d
        }
        let id = str("Id from get_state")
        let eases = ZoomEase.allCases.map(\.rawValue)
        let kinds = AnnotationKind.allCases.map(\.rawValue)
        let annotationLook: [String: Any] = [
            "start": num("Seconds. Default: the playhead."),
            "end": num("Seconds. Default: start + 3."),
            "x1": num("Arrow tail, rectangle/spotlight/blur corner, or text top-left (0...1)."),
            "y1": num("0...1"),
            "x2": num("Arrow head or opposite corner (0...1). Unused for text."),
            "y2": num("0...1"),
            "text": str("Text content (kind text)."),
            "color": str("red, orange, yellow, green, blue, purple, white, black, or #RRGGBB."),
            "width": num("Line thickness, font size (text), darkness % (spotlight) or strength (blur)."),
            "arrow_style": str("Arrow look.", ArrowStyle.allCases.map(\.rawValue)),
            "rect_style": str("Rectangle look.", RectStyle.allCases.map(\.rawValue)),
            "font": str("Text font.", FontStyle.allCases.map(\.rawValue)),
            "bold": ["type": "boolean"],
            "text_box": str("Text background.", TextBox.allCases.map(\.rawValue)),
            "blur_style": str("Blur effect.", BlurStyle.allCases.map(\.rawValue)),
        ]
        var add = annotationLook
        add["kind"] = str("What to draw.", kinds)

        return [
            ToolDefinition(name: "get_state", description: "Current video, trim, crop, zoom points and annotations (with ids). Call it first and after edits.", schema: obj([:])),
            ToolDefinition(name: "get_frame", description: "A JPEG of the video at `time`, to see what is on screen. Use it to locate things before placing annotations or zooms.", schema: obj(["time": num("Seconds")], required: ["time"])),
            ToolDefinition(name: "seek", description: "Move the playhead.", schema: obj(["time": num("Seconds")], required: ["time"])),
            ToolDefinition(name: "set_trim", description: "Keep only the part of the video between start and end (seconds).", schema: obj(["start": num("Seconds"), "end": num("Seconds")], required: ["start", "end"])),
            ToolDefinition(name: "set_crop", description: "Crop the frame to a rectangle (0...1, origin top left).", schema: obj(["x": num("Left"), "y": num("Top"), "width": num("Width"), "height": num("Height")], required: ["x", "y", "width", "height"])),
            ToolDefinition(name: "clear_crop", description: "Remove the crop.", schema: obj([:])),
            ToolDefinition(name: "add_zoom", description: "Add a camera waypoint: the camera is at `scale` (1 = whole frame, 2 = twice as close) centered on (x, y) at `time`, travelling there for `transition` seconds before. To zoom in then out, add a point at scale 2 and a later one at scale 1.", schema: obj([
                "time": num("Seconds at which the camera has arrived"), "scale": num("1...8"),
                "x": num("Center x, 0...1 (default 0.5)"), "y": num("Center y, 0...1 (default 0.5)"),
                "transition": num("Travel time in seconds (default 0.6)"), "ease": str("Camera motion", eases),
            ], required: ["time", "scale"])),
            ToolDefinition(name: "update_zoom", description: "Change a zoom point.", schema: obj([
                "id": id, "time": num("Seconds"), "scale": num("1...8"), "x": num("0...1"), "y": num("0...1"),
                "transition": num("Seconds"), "ease": str("Camera motion", eases),
            ], required: ["id"])),
            ToolDefinition(name: "delete_zoom", description: "Delete a zoom point.", schema: obj(["id": id], required: ["id"])),
            ToolDefinition(name: "add_annotation", description: "Draw an arrow, text, rectangle, spotlight (lit area, the rest darkened) or blur on the video between start and end.", schema: obj(add, required: ["kind", "x1", "y1"])),
            ToolDefinition(name: "update_annotation", description: "Change an annotation. Only the given fields change.", schema: obj(annotationLook.merging(["id": id]) { a, _ in a }, required: ["id"])),
            ToolDefinition(name: "delete_annotation", description: "Delete an annotation.", schema: obj(["id": id], required: ["id"])),
            ToolDefinition(name: "track_annotation", description: "Make an annotation follow the content under it (scrolling, moving), from `from` to its end. Waits until tracking is done.", schema: obj(["id": id, "from": num("Seconds. Default: the annotation's start.")], required: ["id"])),
            ToolDefinition(name: "undo", description: "Undo the last change.", schema: obj([:])),
            ToolDefinition(name: "redo", description: "Redo the last undone change.", schema: obj([:])),
            ToolDefinition(name: "export", description: "Export the result with the current export settings. Without `path`, saves next to the original as name-optimized.mp4.", schema: obj(["path": str("Absolute destination file")])),
        ]
    }()

    // MARK: Calling

    /// Runs one tool. Everything one AI turn changes is one undo step if the caller wraps the turn in
    /// `model.beginUndoGroup()` / `endUndoGroup()`.
    func call(_ name: String, _ args: [String: Any] = [:]) async throws -> ToolOutput {
        guard let model = currentModel() else { throw ToolError("No video is open in Méliès.") }
        switch name {
        case "get_state": return ToolOutput(text: Self.json(state(model)))
        case "get_frame": return try await frame(model, args)
        case "seek":
            model.seek(to: try Self.number(args, "time", in: 0...model.duration))
            return ok(model, "Playhead at \(Self.round(model.current)) s.")
        case "set_trim":
            let start = try Self.number(args, "start", in: 0...model.duration)
            let end = try Self.number(args, "end", in: 0...model.duration)
            guard end > start else { throw ToolError("end must be greater than start.") }
            model.start = start
            model.end = end
            return ok(model, "Trim is now \(Self.round(start)) to \(Self.round(end)) s.")
        case "set_crop":
            let x = try Self.number(args, "x", in: 0...1), y = try Self.number(args, "y", in: 0...1)
            let w = try Self.number(args, "width", in: 0.02...1), h = try Self.number(args, "height", in: 0.02...1)
            guard x + w <= 1.0001, y + h <= 1.0001 else { throw ToolError("The crop must stay inside the frame: x + width and y + height must be at most 1.") }
            model.cropMode = false
            model.cropRect = CGRect(x: x, y: y, width: w, height: h)
            model.confirmCrop()
            return ok(model, model.cropRect == nil ? "Crop covers the whole frame, so there is no crop." : "Cropped.")
        case "clear_crop":
            model.cancelCrop()
            return ok(model, "Crop removed.")
        case "add_zoom": return try addZoom(model, args)
        case "update_zoom": return try updateZoom(model, args)
        case "delete_zoom":
            let id = try Self.id(args)
            guard model.zoomPoints.contains(where: { $0.id == id }) else { throw ToolError("No zoom point with this id.") }
            model.zoomPoints.removeAll { $0.id == id }
            return ok(model, "Zoom point deleted.")
        case "add_annotation": return try addAnnotation(model, args)
        case "update_annotation": return try updateAnnotation(model, args)
        case "delete_annotation":
            let id = try Self.id(args)
            guard model.annotations.contains(where: { $0.id == id }) else { throw ToolError("No annotation with this id.") }
            model.annotations.removeAll { $0.id == id }
            return ok(model, "Annotation deleted.")
        case "track_annotation": return try await track(model, args)
        case "undo":
            guard model.canUndo else { throw ToolError("Nothing to undo.") }
            model.undo()
            return ok(model, "Undone.")
        case "redo":
            guard model.canRedo else { throw ToolError("Nothing to redo.") }
            model.redo()
            return ok(model, "Redone.")
        case "export": return try await export(model, args)
        default: throw ToolError("Unknown tool \(name).")
        }
    }

    /// Runs a tool and turns any failure into text for the model.
    func run(_ name: String, _ args: [String: Any] = [:]) async -> (output: ToolOutput, failed: Bool) {
        do { return (try await call(name, args), false) } catch {
            return (ToolOutput(text: error.localizedDescription), true)
        }
    }

    // MARK: Tools

    private func addZoom(_ model: EditorModel, _ args: [String: Any]) throws -> ToolOutput {
        let time = try Self.number(args, "time", in: 0...model.duration)
        let scale = try Self.number(args, "scale", in: 1...8)
        let x = try Self.optional(args, "x", in: 0...1) ?? 0.5, y = try Self.optional(args, "y", in: 0...1) ?? 0.5
        let transition = try Self.optional(args, "transition", in: 0...5) ?? 0.6
        let ease = try Self.optionalEnum(args, "ease", ZoomEase.self) ?? .smooth
        guard !model.zoomPoints.contains(where: { abs($0.time - time) < 0.05 }) else {
            throw ToolError("There is already a zoom point near \(Self.round(time)) s. Use update_zoom, or pick another time.")
        }
        let point = ZoomPoint(time: time, scale: scale, center: ZoomCamera.clampedCenter(CGPoint(x: x, y: y), scale: scale), transition: transition, ease: ease)
        model.zoomPoints.append(point)
        model.zoomPoints.sort { $0.time < $1.time }
        return ok(model, "Zoom point added.", extra: ["id": point.id.uuidString])
    }

    private func updateZoom(_ model: EditorModel, _ args: [String: Any]) throws -> ToolOutput {
        let id = try Self.id(args)
        guard let index = model.zoomPoints.firstIndex(where: { $0.id == id }) else { throw ToolError("No zoom point with this id.") }
        var point = model.zoomPoints[index]
        if let v = try Self.optional(args, "time", in: 0...model.duration) { point.time = v }
        if let v = try Self.optional(args, "scale", in: 1...8) { point.scale = v }
        if let v = try Self.optional(args, "x", in: 0...1) { point.center.x = v }
        if let v = try Self.optional(args, "y", in: 0...1) { point.center.y = v }
        if let v = try Self.optional(args, "transition", in: 0...5) { point.transition = v }
        if let v = try Self.optionalEnum(args, "ease", ZoomEase.self) { point.ease = v }
        point.center = ZoomCamera.clampedCenter(point.center, scale: point.scale)
        model.zoomPoints[index] = point
        model.zoomPoints.sort { $0.time < $1.time }
        return ok(model, "Zoom point updated.")
    }

    private func addAnnotation(_ model: EditorModel, _ args: [String: Any]) throws -> ToolOutput {
        guard let raw = args["kind"] as? String, let kind = AnnotationKind(rawValue: raw) else {
            throw ToolError("kind must be one of \(AnnotationKind.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        let x1 = try Self.number(args, "x1", in: 0...1), y1 = try Self.number(args, "y1", in: 0...1)
        var p2 = CGPoint(x: x1, y: y1)
        if kind != .text {
            guard args["x2"] != nil, args["y2"] != nil else { throw ToolError("\(raw) needs x2 and y2.") }
            p2 = CGPoint(x: try Self.number(args, "x2", in: 0...1), y: try Self.number(args, "y2", in: 0...1))
        }
        let id = model.addAnnotation(kind, at: CGPoint(x: x1, y: y1))
        do {
            try apply(args, to: id, p2: kind == .text ? nil : p2, model: model)
        } catch {
            model.annotations.removeAll { $0.id == id }
            throw error
        }
        return ok(model, "Annotation added.", extra: ["id": id.uuidString])
    }

    private func updateAnnotation(_ model: EditorModel, _ args: [String: Any]) throws -> ToolOutput {
        let id = try Self.id(args)
        guard model.annotations.contains(where: { $0.id == id }) else { throw ToolError("No annotation with this id.") }
        try apply(args, to: id, p2: nil, model: model)
        return ok(model, "Annotation updated.")
    }

    /// Applies the optional fields. Validates first, so a bad value changes nothing.
    private func apply(_ args: [String: Any], to id: UUID, p2: CGPoint?, model: EditorModel) throws {
        let start = try Self.optional(args, "start", in: 0...model.duration)
        let end = try Self.optional(args, "end", in: 0...model.duration)
        let x1 = try Self.optional(args, "x1", in: 0...1), y1 = try Self.optional(args, "y1", in: 0...1)
        let x2 = try Self.optional(args, "x2", in: 0...1), y2 = try Self.optional(args, "y2", in: 0...1)
        let width = try Self.optional(args, "width", in: 1...100)
        let color = try (args["color"] as? String).map(Self.color)
        let arrow = try Self.optionalEnum(args, "arrow_style", ArrowStyle.self)
        let rect = try Self.optionalEnum(args, "rect_style", RectStyle.self)
        let font = try Self.optionalEnum(args, "font", FontStyle.self)
        let box = try Self.optionalEnum(args, "text_box", TextBox.self)
        let blur = try Self.optionalEnum(args, "blur_style", BlurStyle.self)
        if let start, let end, end <= start { throw ToolError("end must be greater than start.") }
        model.updateAnnotation(id) { a in
            if let start { a.start = start }
            if let end { a.end = end }
            if let x1 { a.p1.x = x1 }
            if let y1 { a.p1.y = y1 }
            if let p2 { a.p2 = p2 }
            if let x2 { a.p2.x = x2 }
            if let y2 { a.p2.y = y2 }
            if let text = args["text"] as? String { a.text = text }
            if let color { a.color = color }
            if let width { a.width = width }
            if let arrow { a.arrow = arrow }
            if let rect { a.rect = rect }
            if let font { a.font = font }
            if let bold = args["bold"] as? Bool { a.bold = bold }
            if let box { a.box = box }
            if let blur { a.blur = blur }
            // The shape moved: an old track no longer describes it.
            if x1 != nil || y1 != nil || x2 != nil || y2 != nil { a.track = []; a.trackStart = 0 }
        }
    }

    private func track(_ model: EditorModel, _ args: [String: Any]) async throws -> ToolOutput {
        let id = try Self.id(args)
        guard let a = model.annotations.first(where: { $0.id == id }) else { throw ToolError("No annotation with this id.") }
        guard model.trackingID == nil else { throw ToolError("A tracking is already running.") }
        let from = try Self.optional(args, "from", in: a.start...a.end) ?? a.start
        model.seek(to: from)
        model.startTracking(id)
        guard model.trackingID != nil else { throw ToolError("Nothing to track: the area is too small, or `from` is too close to the end.") }
        while model.trackingID != nil { try await Task.sleep(for: .milliseconds(100)) }
        let tracked = model.annotations.first { $0.id == id }
        let end = tracked.map { Self.round($0.end) } ?? 0
        return ok(model, model.trackingLost ? "Tracking stopped: the content left the frame or was covered. The annotation now ends at \(end) s." : "Tracked until \(end) s.")
    }

    private func export(_ model: EditorModel, _ args: [String: Any]) async throws -> ToolOutput {
        guard !model.busy else { throw ToolError("An export is already running.") }
        let ext = ExportSettings.current.fileExtension
        var target: URL
        if let path = args["path"] as? String, !path.isEmpty {
            target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            if target.pathExtension.isEmpty { target.appendPathExtension(ext) }
        } else {
            let base = model.url.deletingPathExtension().lastPathComponent + "-optimized"
            target = model.url.deletingLastPathComponent().appendingPathComponent(base + "." + ext)
            var n = 2
            while FileManager.default.fileExists(atPath: target.path) {
                target = model.url.deletingLastPathComponent().appendingPathComponent("\(base)-\(n).\(ext)")
                n += 1
            }
        }
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard await model.export(to: target) else { throw ToolError(model.status ?? "Export failed.") }
        let bytes = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ToolOutput(text: Self.json(["exported": target.path, "megabytes": Self.round(Double(bytes) / 1_000_000)]))
    }

    private func frame(_ model: EditorModel, _ args: [String: Any]) async throws -> ToolOutput {
        let time = try Self.number(args, "time", in: 0...model.duration)
        let generator = AVAssetImageGenerator(asset: model.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let result: CGImage
        do {
            result = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600)).image
        } catch { throw ToolError("Could not read the frame at \(Self.round(time)) s.") }
        let rep = NSBitmapImageRep(cgImage: result)
        guard let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else { throw ToolError("Could not encode the frame.") }
        return ToolOutput(text: "Frame at \(Self.round(time)) s. Coordinates are 0...1 across this image, origin top left.", image: jpeg)
    }

    // MARK: State

    private func state(_ model: EditorModel) -> [String: Any] {
        var state: [String: Any] = [
            "file": model.url.lastPathComponent,
            "duration": Self.round(model.duration),
            "fps": Self.round(model.fps),
            "width": Int(model.sourceSize.width),
            "height": Int(model.sourceSize.height),
            "playhead": Self.round(model.current),
            "trim": ["start": Self.round(model.start), "end": Self.round(model.end)],
            "has_audio": model.hasAudio,
            "keeps_audio": model.includeAudio,
            "has_recorded_clicks": model.hasClicks,
            "zoom_points": model.zoomPoints.map(Self.describe),
            "annotations": model.annotations.map(Self.describe),
        ]
        if let r = model.cropRect {
            state["crop"] = ["x": Self.round(r.minX), "y": Self.round(r.minY), "width": Self.round(r.width), "height": Self.round(r.height)]
        }
        if let cursor = model.cursor?.position(at: model.current) {
            state["cursor_at_playhead"] = ["x": Self.round(cursor.x), "y": Self.round(cursor.y)]
        }
        return state
    }

    private static func describe(_ p: ZoomPoint) -> [String: Any] {
        ["id": p.id.uuidString, "time": round(p.time), "scale": round(p.scale), "x": round(p.center.x), "y": round(p.center.y),
         "transition": round(p.transition), "ease": p.ease.rawValue]
    }

    private static func describe(_ a: Annotation) -> [String: Any] {
        var d: [String: Any] = [
            "id": a.id.uuidString, "kind": a.kind.rawValue, "start": round(a.start), "end": round(a.end),
            "x1": round(a.p1.x), "y1": round(a.p1.y), "color": hex(a.color), "width": round(a.width), "tracked": a.isTracked,
        ]
        if a.kind != .text { d["x2"] = round(a.p2.x); d["y2"] = round(a.p2.y) }
        if a.kind == .text { d["text"] = a.text }
        return d
    }

    private func ok(_ model: EditorModel, _ message: String, extra: [String: Any] = [:]) -> ToolOutput {
        var result = extra
        result["message"] = message
        return ToolOutput(text: Self.json(result))
    }

    // MARK: Argument helpers

    private static func round(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }

    private static func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]),
              let text = String(data: data, encoding: .utf8) else { return "\(object)" }
        return text
    }

    private static func value(_ args: [String: Any], _ key: String) throws -> Double? {
        guard let raw = args[key], !(raw is NSNull) else { return nil }
        // JSON true/false and the numbers 0/1 all bridge to Bool in Swift, so tell them apart by the CF type.
        guard let n = raw as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { throw ToolError("\(key) must be a number.") }
        return n.doubleValue
    }

    private static func number(_ args: [String: Any], _ key: String, in range: ClosedRange<Double>) throws -> Double {
        guard let v = try optional(args, key, in: range) else { throw ToolError("\(key) is required.") }
        return v
    }

    private static func optional(_ args: [String: Any], _ key: String, in range: ClosedRange<Double>) throws -> Double? {
        guard let v = try value(args, key) else { return nil }
        guard range.contains(v) else { throw ToolError("\(key) must be between \(round(range.lowerBound)) and \(round(range.upperBound)), got \(round(v)).") }
        return v
    }

    private static func optionalEnum<E: RawRepresentable & CaseIterable>(_ args: [String: Any], _ key: String, _ type: E.Type) throws -> E? where E.RawValue == String {
        guard let raw = args[key], !(raw is NSNull) else { return nil }
        guard let s = raw as? String, let e = E(rawValue: s) else {
            throw ToolError("\(key) must be one of \(E.allCases.map(\.rawValue).joined(separator: ", ")).")
        }
        return e
    }

    private static func id(_ args: [String: Any]) throws -> UUID {
        guard let s = args["id"] as? String, let id = UUID(uuidString: s) else { throw ToolError("id is required (take it from get_state).") }
        return id
    }

    private static let named: [String: RGBA] = [
        "red": .red, "orange": .orange, "yellow": .yellow, "green": .green,
        "blue": .blue, "purple": .purple, "white": .white, "black": .black,
    ]

    static func color(_ text: String) throws -> RGBA {
        let s = text.trimmingCharacters(in: .whitespaces).lowercased()
        if let c = named[s] { return c }
        var h = s
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else {
            throw ToolError("color must be one of \(named.keys.sorted().joined(separator: ", ")) or #RRGGBB.")
        }
        return RGBA(r: Double((v >> 16) & 255) / 255, g: Double((v >> 8) & 255) / 255, b: Double(v & 255) / 255, a: 1)
    }

    static func hex(_ c: RGBA) -> String {
        if let name = named.first(where: { $0.value == c })?.key { return name }
        func byte(_ x: Double) -> Int { Int((min(max(x, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
    }
}
