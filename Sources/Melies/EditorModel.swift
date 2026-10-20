import AVFoundation
import AppKit

@MainActor
final class EditorModel: ObservableObject {
    let url: URL
    let asset: AVURLAsset
    let player: AVPlayer

    @Published var duration: Double = 0
    @Published var start: Double = 0
    @Published var end: Double = 0
    @Published var current: Double = 0
    @Published var isPlaying = false
    @Published var busy = false
    @Published var status: String?
    @Published var sourceSize: CGSize = .zero
    @Published var fps: Double = 0

    private var timeObserver: Any?
    private var frameDuration: Double = 1.0 / 30.0

    init(url: URL) {
        self.url = url
        self.asset = AVURLAsset(url: url)
        self.player = AVPlayer(playerItem: AVPlayerItem(asset: asset))
        player.actionAtItemEnd = .pause

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
        seek(to: 0)
    }

    private func tick(_ seconds: Double) {
        guard seconds.isFinite else { return }
        current = seconds
        isPlaying = player.timeControlStatus == .playing
        // Loop inside the trimmed range.
        if isPlaying, seconds >= end - 0.02 { seek(to: start) }
    }

    func seek(to seconds: Double) {
        let t = min(max(seconds, 0), duration)
        current = t
        player.seek(to: CMTime(seconds: t, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePlay() {
        if player.timeControlStatus == .playing {
            player.pause()
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

    private func export(to destination: URL) async -> Bool {
        busy = true
        status = "Export en cours..."
        player.pause()
        defer { busy = false }
        do {
            try await TwitterExport.run(asset: asset, range: range, to: destination)
            return true
        } catch {
            status = "Echec de l'export : \(error.localizedDescription)"
            return false
        }
    }

    private func sizeLabel(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    /// Cmd+C: export to a temp file, then put that file on the pasteboard.
    func copy() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("melies-\(Int(Date().timeIntervalSince1970)).mp4")
        guard await export(to: tmp) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([tmp as NSURL])
        status = "Copie (\(sizeLabel(tmp))). Colle-le dans Twitter."
    }

    /// Export to a temp file and show the system share sheet.
    func share(from view: NSView?) async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("melies-\(Int(Date().timeIntervalSince1970)).mp4")
        guard await export(to: tmp), let view else { return }
        status = "Prêt à partager (\(sizeLabel(tmp)))"
        let picker = NSSharingServicePicker(items: [tmp])
        picker.show(relativeTo: NSRect(x: view.bounds.maxX - 120, y: view.bounds.maxY - 50, width: 1, height: 1),
                    of: view, preferredEdge: .minY)
    }

    /// Cmd+S: export next to the original, never overwriting.
    func save() async {
        let folder = url.deletingLastPathComponent()
        let base = url.deletingPathExtension().lastPathComponent + "-twitter"
        var target = folder.appendingPathComponent(base + ".mp4")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = folder.appendingPathComponent("\(base)-\(n).mp4")
            n += 1
        }
        guard await export(to: target) else { return }
        status = "Enregistre : \(target.lastPathComponent) (\(sizeLabel(target)))"
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }
}
