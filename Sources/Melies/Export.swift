import AVFoundation
import AppKit

enum ExportError: LocalizedError {
    case noVideoTrack
    var errorDescription: String? { "Aucune piste video dans ce fichier." }
}

/// Twitter-friendly export: H.264 MP4, 30 fps, width <= 1920, aspect ratio between 1:3 and 3:1.
enum TwitterExport {
    static let maxWidth: CGFloat = 1920
    static let fps: Int32 = 30

    static func run(asset: AVAsset, range: CMTimeRange, to url: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let assetDuration = try await asset.load(.duration)

        let oriented = natural.applying(preferred)
        let srcW = abs(oriented.width)
        let srcH = abs(oriented.height)

        let scale = min(1, maxWidth / srcW)
        var contentW = (srcW * scale).rounded()
        var contentH = (srcH * scale).rounded()

        // Pad to stay within Twitter's 3:1 / 1:3 aspect ratio limits.
        var outW = contentW
        var outH = contentH
        if contentW / contentH > 3 { outH = (contentW / 3).rounded(.up) }
        if contentH / contentW > 3 { outW = (contentH / 3).rounded(.up) }
        contentW = (contentW / 2).rounded() * 2
        contentH = (contentH / 2).rounded() * 2
        outW = (outW / 2).rounded(.up) * 2
        outH = (outH / 2).rounded(.up) * 2

        // Move the oriented frame back to the origin, scale it, then center it in the canvas.
        let originFix = CGAffineTransform(translationX: -min(0, oriented.width), y: -min(0, oriented.height))
        let transform = preferred
            .concatenating(originFix)
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(CGAffineTransform(translationX: (outW - contentW) / 2, y: (outH - contentH) / 2))

        let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        layer.setTransform(transform, at: .zero)
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: assetDuration)
        instruction.layerInstructions = [layer]
        instruction.backgroundColor = NSColor.black.cgColor

        let composition = AVMutableVideoComposition()
        composition.renderSize = CGSize(width: outW, height: outH)
        composition.frameDuration = CMTime(value: 1, timescale: fps)
        composition.instructions = [instruction]

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.noVideoTrack
        }
        session.timeRange = range
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: url)
        try await session.export(to: url, as: .mp4)
    }
}
