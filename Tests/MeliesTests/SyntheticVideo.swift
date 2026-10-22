import AVFoundation
import CoreGraphics
import XCTest
@testable import Melies

/// Tiny synthetic videos for the tracker tests: H.264, written with AVAssetWriter from pixel buffers
/// drawn with CoreGraphics. Everything is seeded, so a run is reproducible.
enum SyntheticVideo {
    /// SplitMix64: a small seeded generator.
    struct Rng {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Random gray texture made of `block` x `block` cells (blocks survive compression better than pixel noise).
    static func noise(width: Int, height: Int, block: Int = 4, seed: UInt64) -> CGImage {
        var rng = Rng(seed: seed)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let cols = (width + block - 1) / block, rows = (height + block - 1) / block
        var cells = [UInt8](repeating: 0, count: cols * rows)
        for i in cells.indices { cells[i] = UInt8(20 + rng.next() % 216) }
        for y in 0..<height { for x in 0..<width { pixels[y * width + x] = cells[(y / block) * cols + x / block] } }
        let image: CGImage? = pixels.withUnsafeMutableBytes { raw in
            CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
        }
        return image!
    }

    /// Writes `frames` frames at 30 fps. `draw(index, context)` paints one frame in a top-left origin context.
    static func make(width: Int, height: Int, frames: Int, draw: (Int, CGContext) -> Void) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("melies-test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 4_000_000, AVVideoExpectedSourceFrameRateKey: 30],
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        for i in 0..<frames {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            guard let pixels = buffer else { throw CocoaError(.fileWriteUnknown) }
            CVPixelBufferLockBaseAddress(pixels, [])
            if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                ctx.translateBy(x: 0, y: CGFloat(height))
                ctx.scaleBy(x: 1, y: -1)
                draw(i, ctx)
            }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            guard adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: 30)) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        return url
    }
}

/// Lets a Sendable closure reach the Task that runs the tracker.
final class TaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<ObjectTracker.Result, Error>?
    func set(_ t: Task<ObjectTracker.Result, Error>) { lock.lock(); task = t; lock.unlock() }
    func cancel() { lock.lock(); task?.cancel(); lock.unlock() }
}
