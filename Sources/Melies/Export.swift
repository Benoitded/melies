import AVFoundation
import CoreImage
import AppKit

enum ExportError: LocalizedError {
    case noVideoTrack
    var errorDescription: String? { L("export.novideo") }
}

/// Everything needed to draw one output frame. Value type, so the compositor can use it from any thread.
struct RenderPlan {
    var orientation: CGImagePropertyOrientation
    var uprightSize: CGSize      // size of the source after rotation
    var base: CGRect             // crop region in upright pixels, top-left origin
    var canvas: CGSize           // output size
    var content: CGRect          // where the picture sits inside the canvas, top-left origin
    var points: [ZoomPoint]
    var annotations: [Annotation] = []

    /// Draws the frame for `time` (asset time, seconds) from the raw source image.
    func render(_ source: CIImage, at time: Double) -> CIImage {
        var image = source.oriented(orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))

        let state = ZoomCamera.state(at: time, points: points)
        let w = base.width / state.scale
        let h = base.height / state.scale
        let x = base.minX + (state.center.x - 0.5 / state.scale) * base.width
        let y = base.minY + (state.center.y - 0.5 / state.scale) * base.height
        // Core Image has a bottom-left origin.
        let region = CGRect(x: x, y: uprightSize.height - (y + h), width: w, height: h)

        let placed = image
            .cropped(to: region)
            .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
            .transformed(by: CGAffineTransform(scaleX: content.width / w, y: content.height / h))
            .transformed(by: CGAffineTransform(translationX: content.minX, y: canvas.height - content.maxY))

        let background = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: canvas))
        var frame = placed.composited(over: background)
        if let overlay = AnnotationRenderer.overlay(annotations, at: time, source: uprightSize,
                                                    region: CGRect(x: x, y: y, width: w, height: h),
                                                    content: content, canvas: canvas) {
            frame = overlay.composited(over: frame)
        }
        return frame
    }
}

final class FrameInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let plan: RenderPlan

    init(timeRange: CMTimeRange, trackID: CMPersistentTrackID, plan: RenderPlan) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: trackID)]
        self.plan = plan
    }
}

/// Custom compositor: crop, zoom camera, scaling and padding in one Core Image pass per frame.
/// Annotations (arrows, text, ...) will be drawn here too, so the preview and the export agree.
final class FrameCompositor: NSObject, AVVideoCompositing {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let pixelFormat = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]

    var sourcePixelBufferAttributes: [String: any Sendable]? { pixelFormat }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { pixelFormat }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? FrameInstruction,
              let trackID = (instruction.requiredSourceTrackIDs?.first as? NSNumber)?.int32Value,
              let source = request.sourceFrame(byTrackID: trackID),
              let target = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "Melies", code: 1))
            return
        }
        let input = CIImage(cvPixelBuffer: source)
        let output = instruction.plan.render(input, at: request.compositionTime.seconds)
        let space = input.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        Self.context.render(output, to: target, bounds: CGRect(origin: .zero, size: instruction.plan.canvas), colorSpace: space)
        request.finish(withComposedVideoFrame: target)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

/// Share-friendly export: H.264 MP4, 30 fps, width <= 1920, aspect ratio between 1:3 and 3:1
/// (so Twitter and most apps accept it), with optional crop and zoom animation.
enum VideoExport {
    static let maxWidth: CGFloat = 1920
    static let fps: Int32 = 30

    /// `crop` is normalized (0...1) in the upright frame, origin top-left.
    static func run(asset: AVAsset, range: CMTimeRange, crop: CGRect? = nil, points: [ZoomPoint] = [], annotations: [Annotation] = [], to url: URL) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }
        let natural = try await track.load(.naturalSize)
        let preferred = try await track.load(.preferredTransform)
        let assetDuration = try await asset.load(.duration)

        let oriented = natural.applying(preferred)
        let srcW = abs(oriented.width)
        let srcH = abs(oriented.height)

        let region = crop ?? CGRect(x: 0, y: 0, width: 1, height: 1)
        let base = CGRect(
            x: (region.minX * srcW).rounded(), y: (region.minY * srcH).rounded(),
            width: max((region.width * srcW).rounded(), 2), height: max((region.height * srcH).rounded(), 2)
        )

        let scale = min(1, maxWidth / base.width)
        var contentW = (base.width * scale).rounded()
        var contentH = (base.height * scale).rounded()

        // Pad to stay within the 3:1 / 1:3 aspect ratio limits.
        var outW = contentW
        var outH = contentH
        if contentW / contentH > 3 { outH = (contentW / 3).rounded(.up) }
        if contentH / contentW > 3 { outW = (contentH / 3).rounded(.up) }
        contentW = (contentW / 2).rounded() * 2
        contentH = (contentH / 2).rounded() * 2
        outW = (outW / 2).rounded(.up) * 2
        outH = (outH / 2).rounded(.up) * 2

        let plan = RenderPlan(
            orientation: orientation(for: preferred),
            uprightSize: CGSize(width: srcW, height: srcH),
            base: base,
            canvas: CGSize(width: outW, height: outH),
            content: CGRect(x: (outW - contentW) / 2, y: (outH - contentH) / 2, width: contentW, height: contentH),
            points: points.sorted { $0.time < $1.time },
            annotations: annotations
        )

        let composition = AVMutableVideoComposition()
        composition.customVideoCompositorClass = FrameCompositor.self
        composition.renderSize = plan.canvas
        composition.frameDuration = CMTime(value: 1, timescale: fps)
        composition.instructions = [
            FrameInstruction(timeRange: CMTimeRange(start: .zero, duration: assetDuration), trackID: track.trackID, plan: plan),
        ]

        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.noVideoTrack
        }
        session.timeRange = range
        session.videoComposition = composition
        session.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: url)
        try await session.export(to: url, as: .mp4)
    }

    /// Maps a track's preferred transform (iPhone portrait clips are rotated) to an image orientation.
    private static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
