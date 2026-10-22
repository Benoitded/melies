import AVFoundation
import AppKit
import CoreImage

enum ComposeLayout: String, CaseIterable {
    case sideBySide, stacked, pip
}

enum PipCorner: String, CaseIterable {
    case topLeading, topTrailing, bottomLeading, bottomTrailing
}

struct ComposeOptions: Equatable {
    var layout: ComposeLayout = .sideBySide
    var gap: CGFloat = 12
    var pipCorner: PipCorner = .bottomTrailing
    var pipScale: CGFloat = 0.3
}

/// Where each video lands in the combined canvas. Shared by the preview in the Combine window and the render.
enum ComposeGeometry {
    static func even(_ v: CGFloat) -> CGFloat { (v / 2).rounded(.up) * 2 }

    /// Canvas size and one rectangle per video, top-left origin. `a` and `b` are the upright video sizes.
    static func layout(a: CGSize, b: CGSize, options o: ComposeOptions) -> (canvas: CGSize, rectA: CGRect, rectB: CGRect) {
        let a = CGSize(width: max(a.width, 2), height: max(a.height, 2))
        let b = CGSize(width: max(b.width, 2), height: max(b.height, 2))

        switch o.layout {
        case .sideBySide:
            var h = min(1080, max(a.height, b.height))
            var wA = a.width * h / a.height, wB = b.width * h / b.height
            var gap = o.gap
            let total = wA + gap + wB
            if total > 2560 {
                let k = 2560 / total
                h *= k; wA *= k; wB *= k; gap *= k
            }
            let canvas = CGSize(width: even(wA + gap + wB), height: even(h))
            return (canvas, CGRect(x: 0, y: 0, width: wA, height: h), CGRect(x: wA + gap, y: 0, width: wB, height: h))

        case .stacked:
            var w = min(1920, max(a.width, b.width))
            var hA = a.height * w / a.width, hB = b.height * w / b.width
            var gap = o.gap
            let total = hA + gap + hB
            if total > 2560 {
                let k = 2560 / total
                w *= k; hA *= k; hB *= k; gap *= k
            }
            let canvas = CGSize(width: even(w), height: even(hA + gap + hB))
            return (canvas, CGRect(x: 0, y: 0, width: w, height: hA), CGRect(x: 0, y: hA + gap, width: w, height: hB))

        case .pip:
            let w = min(1920, a.width)
            let h = a.height * w / a.width
            let canvas = CGSize(width: even(w), height: even(h))
            let pipW = canvas.width * o.pipScale
            let pipH = pipW * b.height / b.width
            let margin = canvas.width * 0.03
            let x = (o.pipCorner == .topLeading || o.pipCorner == .bottomLeading) ? margin : canvas.width - pipW - margin
            let y = (o.pipCorner == .topLeading || o.pipCorner == .topTrailing) ? margin : canvas.height - pipH - margin
            return (canvas, CGRect(origin: .zero, size: canvas), CGRect(x: x, y: y, width: pipW, height: pipH))
        }
    }
}

struct ComposePlan {
    var canvas: CGSize
    var rectA: CGRect
    var rectB: CGRect
    var orientationA: CGImagePropertyOrientation
    var orientationB: CGImagePropertyOrientation
    var trackA: CMPersistentTrackID
    var trackB: CMPersistentTrackID
    var pip: Bool

    private func place(_ source: CIImage, orientation: CGImagePropertyOrientation, in rect: CGRect) -> CIImage {
        var image = source.oriented(orientation)
        image = image.transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
        let sx = rect.width / image.extent.width, sy = rect.height / image.extent.height
        return image
            .transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: rect.minX, y: canvas.height - rect.maxY))
    }

    /// Rounded corners, a thin light border and a soft shadow for the picture-in-picture.
    private func pipDecoration() -> (mask: CIImage, frame: CIImage)? {
        let w = Int(canvas.width), h = Int(canvas.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        func context() -> CGContext? {
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            ctx?.translateBy(x: 0, y: canvas.height)
            ctx?.scaleBy(x: 1, y: -1)
            return ctx
        }
        let radius = rectB.width * 0.06
        let path = CGPath(roundedRect: rectB, cornerWidth: radius, cornerHeight: radius, transform: nil)
        guard let maskContext = context(), let frameContext = context() else { return nil }
        maskContext.setFillColor(CGColor(gray: 1, alpha: 1))
        maskContext.addPath(path)
        maskContext.fillPath()

        frameContext.saveGState()
        frameContext.setShadow(offset: CGSize(width: 0, height: canvas.width * 0.004), blur: canvas.width * 0.012, color: CGColor(gray: 0, alpha: 0.5))
        frameContext.setFillColor(CGColor(gray: 0, alpha: 1))
        frameContext.addPath(path)
        frameContext.fillPath()
        frameContext.restoreGState()
        frameContext.setStrokeColor(CGColor(gray: 1, alpha: 0.55))
        frameContext.setLineWidth(max(canvas.width * 0.0016, 1.5))
        frameContext.addPath(path)
        frameContext.strokePath()

        guard let maskImage = maskContext.makeImage(), let frameImage = frameContext.makeImage() else { return nil }
        return (CIImage(cgImage: maskImage), CIImage(cgImage: frameImage))
    }

    func render(a: CIImage?, b: CIImage?) -> CIImage {
        let bounds = CGRect(origin: .zero, size: canvas)
        var result = CIImage(color: .black).cropped(to: bounds)
        if let a { result = place(a, orientation: orientationA, in: rectA).cropped(to: bounds).composited(over: result) }
        guard let b else { return result }
        var placed = place(b, orientation: orientationB, in: rectB)
        if pip, let decoration = pipDecoration() {
            result = decoration.frame.composited(over: result)
            placed = placed.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: CIImage.empty(), kCIInputMaskImageKey: decoration.mask])
        }
        return placed.cropped(to: bounds).composited(over: result)
    }
}

final class ComposeInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    let requiredSourceTrackIDs: [NSValue]?
    let passthroughTrackID = kCMPersistentTrackID_Invalid
    let plan: ComposePlan

    init(timeRange: CMTimeRange, plan: ComposePlan) {
        self.timeRange = timeRange
        self.requiredSourceTrackIDs = [NSNumber(value: plan.trackA), NSNumber(value: plan.trackB)]
        self.plan = plan
    }
}

/// Draws two videos into one frame. When one video ends before the other, its last frame stays on screen.
final class ComposeCompositor: NSObject, AVVideoCompositing {
    private static let context = CIContext(options: [.cacheIntermediates: false])
    private let pixelFormat = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
    private let lock = NSLock()
    private var lastFrames: [CMPersistentTrackID: CIImage] = [:]

    var sourcePixelBufferAttributes: [String: any Sendable]? { pixelFormat }
    var requiredPixelBufferAttributesForRenderContext: [String: any Sendable] { pixelFormat }

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {}

    private func frame(for track: CMPersistentTrackID, in request: AVAsynchronousVideoCompositionRequest) -> CIImage? {
        lock.lock(); defer { lock.unlock() }
        if let buffer = request.sourceFrame(byTrackID: track) {
            let image = CIImage(cvPixelBuffer: buffer)
            lastFrames[track] = image
            return image
        }
        return lastFrames[track]
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        guard let instruction = request.videoCompositionInstruction as? ComposeInstruction,
              let target = request.renderContext.newPixelBuffer() else {
            request.finish(with: NSError(domain: "Melies", code: 2))
            return
        }
        let plan = instruction.plan
        let a = frame(for: plan.trackA, in: request)
        let b = frame(for: plan.trackB, in: request)
        let output = plan.render(a: a, b: b)
        let space = a?.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        Self.context.render(output, to: target, bounds: CGRect(origin: .zero, size: plan.canvas), colorSpace: space)
        request.finish(withComposedVideoFrame: target)
    }

    func cancelAllPendingVideoCompositionRequests() {}
}

enum ComposeExport {
    static func uprightSize(of asset: AVAsset) async throws -> (size: CGSize, orientation: CGImagePropertyOrientation) {
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw ExportError.noVideoTrack }
        let natural = try await track.load(.naturalSize)
        let t = try await track.load(.preferredTransform)
        let o = natural.applying(t)
        let orientation: CGImagePropertyOrientation
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): orientation = .right
        case (0, -1, 1, 0): orientation = .left
        case (-1, 0, 0, -1): orientation = .down
        default: orientation = .up
        }
        return (CGSize(width: abs(o.width), height: abs(o.height)), orientation)
    }

    /// Combines two videos into one MP4. Returns when the file is written.
    static func run(a: URL, b: URL, options: ComposeOptions, to url: URL) async throws {
        let assetA = AVURLAsset(url: a), assetB = AVURLAsset(url: b)
        let infoA = try await uprightSize(of: assetA), infoB = try await uprightSize(of: assetB)
        let durationA = try await assetA.load(.duration), durationB = try await assetB.load(.duration)
        let geometry = ComposeGeometry.layout(a: infoA.size, b: infoB.size, options: options)

        let composition = AVMutableComposition()
        guard let sourceA = try await assetA.loadTracks(withMediaType: .video).first,
              let sourceB = try await assetB.loadTracks(withMediaType: .video).first,
              let trackA = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let trackB = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ExportError.noVideoTrack }
        try trackA.insertTimeRange(CMTimeRange(start: .zero, duration: durationA), of: sourceA, at: .zero)
        try trackB.insertTimeRange(CMTimeRange(start: .zero, duration: durationB), of: sourceB, at: .zero)

        // Keep the sound of both videos, if they have any.
        for (asset, duration) in [(assetA, durationA), (assetB, durationB)] {
            if let audio = try await asset.loadTracks(withMediaType: .audio).first,
               let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio, at: .zero)
            }
        }

        let total = CMTimeMaximum(durationA, durationB)
        let plan = ComposePlan(
            canvas: geometry.canvas, rectA: geometry.rectA, rectB: geometry.rectB,
            orientationA: infoA.orientation, orientationB: infoB.orientation,
            trackA: trackA.trackID, trackB: trackB.trackID, pip: options.layout == .pip
        )
        let videoComposition = AVMutableVideoComposition()
        videoComposition.customVideoCompositorClass = ComposeCompositor.self
        videoComposition.renderSize = plan.canvas
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        videoComposition.instructions = [ComposeInstruction(timeRange: CMTimeRange(start: .zero, duration: total), plan: plan)]

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.noVideoTrack
        }
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = true
        try? FileManager.default.removeItem(at: url)
        try await session.export(to: url, as: .mp4)
    }
}
