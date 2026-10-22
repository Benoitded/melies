import AVFoundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class EditorModel: ObservableObject {
    let url: URL
    let asset: AVURLAsset
    let player: AVPlayer

    @Published var duration: Double = 0
    @Published var start: Double = 0 { didSet { noteChange() } }
    @Published var end: Double = 0 { didSet { noteChange() } }
    @Published var current: Double = 0
    @Published var isPlaying = false
    @Published var busy = false
    @Published var status: String?
    @Published var sourceSize: CGSize = .zero
    @Published var fps: Double = 0
    /// Crop region, normalized (0...1) in the upright frame, origin top-left. nil means no crop.
    @Published var cropRect: CGRect? { didSet { noteChange() } }
    @Published var cropMode = false
    /// The video has an audio track; `includeAudio` decides whether the export keeps it.
    @Published var hasAudio = false
    /// Draw a ring at every recorded click (preview and export).
    @Published var showClicks = ClickStyleStore.enabled
    var hasClicks: Bool { !(cursor?.clicks.isEmpty ?? true) }
    @Published var includeAudio = true
    @Published var thumbnails: [NSImage] = []
    @Published var zoomPoints: [ZoomPoint] = [] { didSet { noteChange() } }
    @Published var selectedPointID: UUID?
    @Published var tool: Tool = .select
    @Published var annotations: [Annotation] = [] { didSet { noteChange(); refreshStillFrame() } }
    @Published var selectedAnnotationID: UUID?
    /// True while a text field has the keyboard, so single-key shortcuts must stay quiet.
    @Published var isEditingText = false
    @Published var textFocusTick = 0
    /// A new text annotation asks for the keyboard; the panel takes it as soon as it appears.
    var wantsTextFocus = false
    /// Set while an annotation drag is in progress, so panning the canvas does not also run.
    var annotationGestureActive = false

    // Preview of blur: the latest decoded frame, upright, taken from the player.
    private var frameOutput: AVPlayerItemVideoOutput?
    private var lastBuffer: CVPixelBuffer?
    // While paused the player does not hand out new frames, so the blur preview asks for the frame itself.
    private var stillFrame: CIImage?
    private var stillFrameTime = -1.0
    private var stillRequestedTime = -1.0
    private var stillRequestID = 0
    private lazy var stillGenerator: AVAssetImageGenerator = {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return generator
    }()
    private var orientation: CGImagePropertyOrientation = .up
    static let previewContext = CIContext()
    var cursor: CursorTrack?
    /// Canvas zoom: 1 means "fit in the window". `pan` moves the video from its fitted center.
    @Published var zoom: Double = 1
    @Published var pan: CGSize = .zero
    /// Size and window position of the video canvas, kept up to date by the view.
    var canvasSize: CGSize = .zero
    var canvasOrigin: CGPoint = .zero

    private var timeObserver: Any?
    private var shareDelegate: ShareDelegate?
    private var frameDuration: Double = 1.0 / 30.0

    init(url: URL) {
        self.url = url
        self.asset = AVURLAsset(url: url)
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .pause
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        player.currentItem?.add(output)
        frameOutput = output

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 60), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.tick(time.seconds) }
        }
        Task { await load() }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
    }

    private func load() async {
        let d = (try? await asset.load(.duration).seconds) ?? 0
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let rate = try? await track.load(.nominalFrameRate), rate > 0 {
                fps = Double(rate)
                frameDuration = 1.0 / Double(min(rate, 60))
            }
            if let natural = try? await track.load(.naturalSize),
               let transform = try? await track.load(.preferredTransform) {
                let o = natural.applying(transform)
                sourceSize = CGSize(width: abs(o.width), height: abs(o.height))
            }
        }
        duration = d.isFinite ? d : 0
        end = duration
        hasAudio = !((try? await asset.loadTracks(withMediaType: .audio)) ?? []).isEmpty
        cursor = CursorTrack.load(for: url)
        if let info = try? await ComposeExport.uprightSize(of: asset) { orientation = info.orientation }
        resetHistory()
        seek(to: 0)
        await generateThumbnails()
    }

    /// A strip of frames for the timeline, like the trim bar in Photos.
    private func generateThumbnails() async {
        guard duration > 0 else { return }
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 360, height: 180)
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity

        let count = 24
        let times = (0..<count).map {
            CMTime(seconds: duration * (Double($0) + 0.5) / Double(count), preferredTimescale: 600)
        }
        var frames = [NSImage?](repeating: nil, count: count)
        do {
            for try await result in generator.images(for: times) {
                if let index = times.firstIndex(of: result.requestedTime) {
                    frames[index] = NSImage(cgImage: try result.image, size: .zero)
                }
            }
        } catch {}
        // Fill any gap with the previous frame so the strip never has holes.
        var last: NSImage?
        thumbnails = frames.compactMap { frame in
            if let frame { last = frame }
            return last
        }
    }

    // MARK: Undo / redo

    /// Everything the user edits. Navigation (playhead, selection, canvas zoom) is not part of it.
    struct Snapshot {
        var annotations: [Annotation] = []
        var zoomPoints: [ZoomPoint] = []
        var cropRect: CGRect?
        var start: Double = 0
        var end: Double = 0
    }

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var committed = Snapshot()
    private var inBurst = false
    private var burstWork: DispatchWorkItem?
    private var restoring = false

    var canUndo: Bool { !undoStack.isEmpty || inBurst }
    var canRedo: Bool { !redoStack.isEmpty }

    private func snapshot() -> Snapshot {
        Snapshot(annotations: annotations, zoomPoints: zoomPoints, cropRect: cropRect, start: start, end: end)
    }

    /// Called whenever edited state changes. Changes less than 0.6 s apart (a drag, a slider, typing)
    /// form one burst, which is one undo step.
    private func noteChange() {
        guard !restoring else { return }
        if !inBurst {
            undoStack.append(committed)
            if undoStack.count > 100 { undoStack.removeFirst() }
            redoStack.removeAll()
            inBurst = true
        }
        burstWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.endBurst() }
        burstWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func endBurst() {
        burstWork?.cancel()
        guard inBurst else { return }
        inBurst = false
        committed = snapshot()
    }

    func resetHistory() {
        burstWork?.cancel()
        inBurst = false
        undoStack.removeAll()
        redoStack.removeAll()
        committed = snapshot()
    }

    func undo() {
        endBurst()
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(snapshot())
        restore(previous)
    }

    func redo() {
        endBurst()
        guard let next = redoStack.popLast() else { return }
        undoStack.append(snapshot())
        restore(next)
    }

    private func restore(_ s: Snapshot) {
        restoring = true
        annotations = s.annotations
        zoomPoints = s.zoomPoints
        cropRect = s.cropRect
        start = s.start
        end = s.end
        restoring = false
        committed = s
        if !annotations.contains(where: { $0.id == selectedAnnotationID }) { selectedAnnotationID = nil }
        if !zoomPoints.contains(where: { $0.id == selectedPointID }) { selectedPointID = nil }
        if cropRect == nil { cropMode = false }
    }

    // MARK: Zoom (canvas only, the exported video is not affected)

    func fitRect(in size: CGSize) -> CGRect {
        let area = CGRect(origin: .zero, size: size)
        guard displaySize.width > 0, size.width > 0, size.height > 0 else { return area }
        return AVMakeRect(aspectRatio: displaySize, insideRect: area)
    }

    /// Where the video is drawn inside the canvas, including zoom and pan.
    func videoRect(in size: CGSize) -> CGRect {
        let fit = fitRect(in: size)
        let w = fit.width * zoom, h = fit.height * zoom
        return CGRect(x: fit.midX + pan.width - w / 2, y: fit.midY + pan.height - h / 2, width: w, height: h)
    }

    private var maxZoom: Double {
        let fit = fitRect(in: canvasSize)
        return fit.width > 0 ? min(8, 12000 / Double(fit.width)) : 8
    }

    private var backingScale: Double { Double(NSScreen.main?.backingScaleFactor ?? 2) }

    /// Zoom percentage as in Shottr: 100% is one video pixel per screen pixel.
    var zoomPercent: Int {
        let width = videoRect(in: canvasSize).width
        guard displaySize.width > 0, width > 0 else { return 100 }
        return Int((Double(width) * backingScale / Double(displaySize.width) * 100).rounded())
    }

    /// Zoom keeping the point under `anchor` (canvas coordinates) fixed. Defaults to the center.
    func setZoom(_ value: Double, anchor: CGPoint? = nil) {
        let new = min(max(value, 0.25), maxZoom)
        guard new != zoom, canvasSize.width > 0 else { return }
        let fit = fitRect(in: canvasSize)
        let a = anchor ?? CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let center = CGPoint(x: fit.midX + pan.width, y: fit.midY + pan.height)
        let ratio = new / zoom
        let newCenter = CGPoint(x: a.x - (a.x - center.x) * ratio, y: a.y - (a.y - center.y) * ratio)
        zoom = new
        pan = CGSize(width: newCenter.x - fit.midX, height: newCenter.y - fit.midY)
        clampPan()
    }

    func panBy(_ delta: CGSize) {
        pan = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
        clampPan()
    }

    /// Keep at least a strip of the video on screen, and re-center when it fits.
    private func clampPan() {
        guard zoom > 1.0001 else { pan = .zero; return }
        let fit = fitRect(in: canvasSize)
        let maxX = max(0, (fit.width * zoom + canvasSize.width) / 2 - 80)
        let maxY = max(0, (fit.height * zoom + canvasSize.height) / 2 - 80)
        pan = CGSize(width: min(max(pan.width, -maxX), maxX), height: min(max(pan.height, -maxY), maxY))
    }

    func zoomIn() { setZoom(zoom * 1.25) }
    func zoomOut() { setZoom(zoom / 1.25) }
    func zoomToFit() { zoom = 1; pan = .zero }

    func zoomActual(anchor: CGPoint? = nil) {
        let fit = fitRect(in: canvasSize)
        guard fit.width > 0, displaySize.width > 0 else { return }
        setZoom(Double(displaySize.width) / backingScale / Double(fit.width), anchor: anchor)
    }

    /// Double click: jump to 100% under the pointer, or back to fit.
    func toggleActual(at point: CGPoint) {
        if abs(zoomPercent - 100) <= 2 { zoomToFit() } else { zoomActual(anchor: point) }
    }

    // MARK: Zoom animation (camera waypoints)

    /// Crop region (or the whole frame), normalized in the source.
    var baseRect: CGRect { cropRect ?? CGRect(x: 0, y: 0, width: 1, height: 1) }

    var baseSize: CGSize {
        CGSize(width: sourceSize.width * baseRect.width, height: sourceSize.height * baseRect.height)
    }

    /// With zoom points and nothing selected, the canvas shows the result of the camera.
    var previewingCamera: Bool { !zoomPoints.isEmpty && selectedPointID == nil && !cropMode }

    var displaySize: CGSize { previewingCamera ? baseSize : sourceSize }

    var selectedPoint: ZoomPoint? { zoomPoints.first { $0.id == selectedPointID } }

    /// Region of the source the camera shows at time `t`, normalized.
    func cameraRegion(at t: Double) -> CGRect {
        ZoomCamera.region(of: ZoomCamera.state(at: t, points: zoomPoints), in: baseRect)
    }

    func region(of point: ZoomPoint) -> CGRect {
        ZoomCamera.region(of: CameraState(scale: point.scale, center: ZoomCamera.clampedCenter(point.center, scale: point.scale)), in: baseRect)
    }

    /// Where a new zoom should point: under the recorded cursor when we have it, else the middle.
    private func smartCenter(at t: Double, scale: Double) -> CGPoint {
        var center = CGPoint(x: 0.5, y: 0.5)
        if let p = cursor?.position(at: t) {
            let b = baseRect
            center = CGPoint(x: (p.x - b.minX) / b.width, y: (p.y - b.minY) / b.height)
        }
        center = CGPoint(x: min(max(center.x, 0), 1), y: min(max(center.y, 0), 1))
        return ZoomCamera.clampedCenter(center, scale: scale)
    }

    /// Z: the first time, creates a zoom with a start and an end. Afterwards, adds a waypoint at the playhead.
    func addZoom() {
        cropMode = false
        let t = min(max(current, 0), duration)
        if zoomPoints.isEmpty {
            let lead = 0.6, hold = 2.4
            var arrive = t + lead
            var leave = arrive + hold
            let limit = max(duration - 0.05, 0.2)
            if leave > limit { let shift = leave - limit; arrive -= shift; leave -= shift }
            arrive = max(arrive, 0.1)
            leave = max(leave, arrive + 0.4)
            let first = ZoomPoint(time: arrive, scale: 2, center: smartCenter(at: arrive, scale: 2), transition: min(lead, arrive), ease: .smooth)
            let last = ZoomPoint(time: min(leave, duration), scale: 1, center: CGPoint(x: 0.5, y: 0.5), transition: 0.7, ease: .smooth)
            zoomPoints = [first, last]
            selectPoint(first.id)
        } else if let existing = zoomPoints.first(where: { abs($0.time - t) < 0.08 }) {
            selectPoint(existing.id)
        } else {
            let state = ZoomCamera.state(at: t, points: zoomPoints)
            var point = ZoomPoint(time: t, scale: state.scale, center: state.center, transition: 0.6, ease: .smooth)
            if state.scale <= 1.01 { point.scale = 2; point.center = smartCenter(at: t, scale: 2) }
            zoomPoints.append(point)
            zoomPoints.sort { $0.time < $1.time }
            selectPoint(point.id)
        }
    }

    func selectPoint(_ id: UUID?) {
        selectedPointID = id
        if let point = selectedPoint {
            selectedAnnotationID = nil
            tool = .select
            player.pause()
            seek(to: point.time)
        }
    }

    func updateSelected(_ change: (inout ZoomPoint) -> Void) {
        guard let index = zoomPoints.firstIndex(where: { $0.id == selectedPointID }) else { return }
        change(&zoomPoints[index])
        zoomPoints[index].scale = min(max(zoomPoints[index].scale, 1), 8)
        zoomPoints[index].transition = min(max(zoomPoints[index].transition, 0), 5)
        zoomPoints[index].center = ZoomCamera.clampedCenter(zoomPoints[index].center, scale: zoomPoints[index].scale)
    }

    /// Dragging a point along the timeline keeps it between its neighbours.
    func movePoint(_ id: UUID, to time: Double) {
        guard let index = zoomPoints.firstIndex(where: { $0.id == id }) else { return }
        let low = index > 0 ? zoomPoints[index - 1].time + 0.05 : 0
        let high = index < zoomPoints.count - 1 ? zoomPoints[index + 1].time - 0.05 : duration
        zoomPoints[index].time = min(max(time, low), max(high, low))
        seek(to: zoomPoints[index].time)
    }

    func deleteSelected() {
        if let id = selectedAnnotationID {
            annotations.removeAll { $0.id == id }
            selectedAnnotationID = nil
        } else if selectedPointID != nil {
            zoomPoints.removeAll { $0.id == selectedPointID }
            selectedPointID = nil
        }
    }

    // MARK: Annotations (arrow, text, rectangle)

    var selectedAnnotation: Annotation? { annotations.first { $0.id == selectedAnnotationID } }

    func setTool(_ new: Tool) {
        tool = new
        if new != .select {
            selectedPointID = nil
            selectedAnnotationID = nil
            cropMode = false
        }
    }

    func selectAnnotation(_ id: UUID?) {
        selectedAnnotationID = id
        guard let a = selectedAnnotation else { return }
        selectedPointID = nil
        cropMode = false
        if current < a.start || current > a.end { seek(to: a.start) }
    }

    /// Creates an annotation visible for 3 seconds from the playhead, with the last style used for its kind.
    func addAnnotation(_ kind: AnnotationKind, at point: CGPoint) -> UUID {
        let style = AnnotationStyleStore.style(for: kind)
        let start = min(max(current, 0), max(duration - 0.3, 0))
        let end = min(start + 3, max(duration, start + 0.3))
        let annotation = Annotation(
            kind: kind, start: start, end: end, p1: point, p2: point, color: style.color, width: style.width,
            arrow: style.arrow, rect: style.rect, text: kind == .text ? L("ann.default_text") : "",
            font: style.font, bold: style.bold, box: style.box, blur: style.blur
        )
        annotations.append(annotation)
        return annotation.id
    }

    func updateAnnotation(_ id: UUID, remember: Bool = false, _ change: (inout Annotation) -> Void) {
        guard let i = annotations.firstIndex(where: { $0.id == id }) else { return }
        change(&annotations[i])
        annotations[i].start = min(max(annotations[i].start, 0), duration)
        annotations[i].end = min(max(annotations[i].end, annotations[i].start + 0.2), max(duration, annotations[i].start + 0.2))
        if remember {
            let a = annotations[i]
            AnnotationStyleStore.save(AnnotationStyle(color: a.color, width: a.width, arrow: a.arrow, rect: a.rect, font: a.font, bold: a.bold, box: a.box, blur: a.blur), for: a.kind)
        }
    }

    func updateSelectedAnnotation(_ change: (inout Annotation) -> Void) {
        guard let id = selectedAnnotationID else { return }
        updateAnnotation(id, remember: true, change)
    }

    func requestTextFocus() {
        wantsTextFocus = true
        textFocusTick += 1
    }

    // MARK: Crop

    func toggleCrop() {
        if cropMode {
            confirmCrop()
        } else {
            if cropRect == nil { cropRect = CGRect(x: 0, y: 0, width: 1, height: 1) } // default: the whole frame
            cropMode = true
        }
    }

    /// Keep the crop and leave crop mode. A crop that covers the whole frame means no crop.
    func confirmCrop() {
        cropMode = false
        if let r = cropRect, r.width > 0.985, r.height > 0.985 { cropRect = nil }
    }

    func cancelCrop() {
        cropMode = false
        cropRect = nil
    }

    /// Pixel size of the cropped frame, nil when there is no crop.
    var croppedSize: CGSize? {
        guard let r = cropRect, sourceSize.width > 0 else { return nil }
        return CGSize(width: (sourceSize.width * r.width).rounded(), height: (sourceSize.height * r.height).rounded())
    }

    /// Keeps the newest frame for blur patches (only when a blur exists).
    private func captureFrame() {
        guard let output = frameOutput, annotations.contains(where: { $0.kind == .blur }) else { return }
        if let buffer = output.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil) { lastBuffer = buffer }
    }

    /// Paused: fetch the exact frame under the playhead, once per position.
    private func refreshStillFrame() {
        guard !isPlaying, annotations.contains(where: { $0.kind == .blur }), abs(current - stillRequestedTime) > 0.0005 else { return }
        let time = current
        stillRequestedTime = time
        stillRequestID += 1
        let id = stillRequestID
        Task { @MainActor in
            guard let result = try? await stillGenerator.image(at: CMTime(seconds: time, preferredTimescale: 600)), id == stillRequestID else { return }
            var image = CIImage(cgImage: result.image)
            image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            stillFrame = image
            stillFrameTime = time
            objectWillChange.send() // redraw the overlay with the blur applied
        }
    }

    /// The last frame as an upright image with its origin at 0,0.
    var currentFrameImage: CIImage? {
        if !isPlaying, let still = stillFrame, abs(stillFrameTime - current) < 0.01 { return still }
        guard let buffer = lastBuffer else { return nil }
        var image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        return image
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        captureFrame()
        refreshStillFrame()
        current = seconds
        isPlaying = player.timeControlStatus == .playing
        // Loop inside the trimmed range.
        if isPlaying, seconds >= end - 0.02 { seek(to: start) }
    }

    func seek(to seconds: Double) {
        let t = min(max(seconds, 0), duration)
        current = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        refreshStillFrame()
    }

    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
            refreshStillFrame()
        } else {
            if current >= end - 0.02 || current < start { seek(to: start) }
            player.play()
        }
    }

    func setIn() { start = min(current, end - frameDuration) ; if current < start { seek(to: start) } }
    func setOut() { end = max(current, start + frameDuration) }

    func step(frames: Int) {
        player.pause()
        seek(to: current + Double(frames) * frameDuration)
    }

    func setStart(_ value: Double) { start = min(max(0, value), end - frameDuration); seek(to: start) }
    func setEnd(_ value: Double) { end = max(min(duration, value), start + frameDuration); seek(to: end) }

    // MARK: Export

    private var range: CMTimeRange {
        CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
    }

    func export(to destination: URL) async -> Bool {
        busy = true
        status = L("status.exporting")
        player.pause()
        defer { busy = false }
        do {
            try await VideoExport.run(asset: asset, range: range, crop: cropRect, points: zoomPoints, annotations: annotations, clicks: showClicks ? ClickSet.current(for: cursor) : nil, includeAudio: includeAudio, to: destination)
            return true
        } catch {
            status = L("status.fail", error.localizedDescription)
            return false
        }
    }

    private func sizeLabel(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// What is dropped when the user drags the drag handle into another app: the optimized MP4,
    /// exported only when the destination asks for it, like a file promise.
    func dragProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        let name = url.deletingPathExtension().lastPathComponent
        provider.suggestedName = name
        provider.registerFileRepresentation(forTypeIdentifier: ExportSettings.current.contentType.identifier, fileOptions: [], visibility: .all) { completion in
            let progress = Progress(totalUnitCount: 1)
            Task { @MainActor in
                let folder = FileManager.default.temporaryDirectory.appendingPathComponent("melies-drag-\(UUID().uuidString)")
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let file = folder.appendingPathComponent(name + "." + ExportSettings.current.fileExtension)
                if await self.export(to: file) {
                    self.status = L("status.dragged")
                    completion(file, false, nil)
                } else {
                    completion(nil, false, ExportError.noVideoTrack)
                }
                progress.completedUnitCount = 1
            }
            return progress
        }
        return provider
    }

    /// Cmd+C: export to a temp file, then put that file on the pasteboard.
    func copy() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("melies-\(Int(Date().timeIntervalSince1970)).\(ExportSettings.current.fileExtension)")
        guard await export(to: tmp) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([tmp as NSURL])
        status = L("status.copied", sizeLabel(tmp))
        finish(toast: L("toast.copied"))
    }

    /// Export to a temp file and show the system share sheet.
    func share(from view: NSView?) async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("melies-\(Int(Date().timeIntervalSince1970)).\(ExportSettings.current.fileExtension)")
        guard await export(to: tmp), let view else { return }
        status = L("status.share_ready", sizeLabel(tmp))
        let picker = NSSharingServicePicker(items: [tmp])
        let delegate = ShareDelegate { [weak self] chose in
            if chose { self?.finish(toast: nil) }
        }
        shareDelegate = delegate
        picker.delegate = delegate
        picker.show(relativeTo: NSRect(x: view.bounds.maxX - 120, y: view.bounds.maxY - 50, width: 1, height: 1),
                    of: view, preferredEdge: .minY)
    }

    /// Cmd+S: export next to the original, never overwriting.
    func save() async {
        let folder = url.deletingLastPathComponent()
        let ext = ExportSettings.current.fileExtension
        let base = url.deletingPathExtension().lastPathComponent + "-optimized"
        var target = folder.appendingPathComponent(base + "." + ext)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base)-\(n).\(ext)")
            n += 1
        }
        guard await export(to: target) else { return }
        status = L("status.saved", target.lastPathComponent, sizeLabel(target))
        NSWorkspace.shared.activateFileViewerSelecting([target])
        finish(toast: L("toast.saved"))
    }

    /// After a successful copy, save or share, close the editor (and with it the Dock icon).
    private func finish(toast: String?) {
        guard UserDefaults.standard.object(forKey: "closeAfterAction") as? Bool ?? true else { return }
        if let toast { Toast.show(toast) }
        EditorWindowController.shared.close()
    }
}

/// Reports whether the user actually picked a sharing service (nil means the picker was dismissed).
final class ShareDelegate: NSObject, NSSharingServicePickerDelegate {
    private let onChoose: @MainActor (Bool) -> Void
    init(onChoose: @escaping @MainActor (Bool) -> Void) { self.onChoose = onChoose }

    func sharingServicePicker(_ picker: NSSharingServicePicker, didChoose service: NSSharingService?) {
        let chose = service != nil
        Task { @MainActor in self.onChoose(chose) }
    }
}
