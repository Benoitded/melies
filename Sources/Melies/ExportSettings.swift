import AVFoundation
import AppKit
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// What the user chose for exports: MP4 or GIF, an optional size limit, and the maximum width.
struct ExportSettings: Equatable {
    enum Format: String, CaseIterable {
        case mp4, hevc, gif
        var isVideo: Bool { self != .gif }
    }

    var format: Format = .mp4
    /// nil means no limit.
    var maxMegabytes: Int?
    var maxWidth: Int = 1920

    static let sizeChoices: [Int] = [1, 2, 3, 5, 8, 15, 25, 50, 100]
    /// 360p, 480p, 720p, 1080p
    static let widthChoices: [Int] = [640, 854, 1280, 1920]

    static var current: ExportSettings {
        let d = UserDefaults.standard
        let mb = d.integer(forKey: Pref.exportMaxMB)
        let width = d.integer(forKey: Pref.exportMaxWidth)
        return ExportSettings(
            format: Format(rawValue: d.string(forKey: Pref.exportFormat) ?? "") ?? .mp4,
            maxMegabytes: mb > 0 ? mb : nil,
            maxWidth: widthChoices.contains(width) ? width : 1920
        )
    }

    var fileExtension: String { format == .gif ? "gif" : "mp4" }
    var contentType: UTType { format == .gif ? .gif : .mpeg4Movie }

    /// Average video bitrate (bits per second) for a clip of `seconds` shown at `canvas` size.
    func videoBitrate(seconds: Double, canvas: CGSize, hasAudio: Bool) -> Int {
        let seconds = max(seconds, 0.1)
        if let mb = maxMegabytes {
            let totalBits = Double(mb) * 1_000_000 * 8 * 0.93 // a little margin: encoders overshoot
            let audioBits = hasAudio ? 128_000 * seconds : 0
            return Int(min(max((totalBits - audioBits) / seconds, 120_000), 20_000_000))
        }
        // H.265 needs about 40 % fewer bits for the same look.
        let factor = format == .hevc ? 0.6 : 1
        let byPixels = Double(canvas.width * canvas.height) * 30 * 0.1 * factor
        return Int(min(max(byPixels, 1_500_000 * factor), 16_000_000))
    }
}

/// Lets the UI follow and cancel a running export. Safe to call from the encoder queues.
final class ExportControl: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @escaping @Sendable (Double) -> Void) { self.onProgress = onProgress }

    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func report(_ fraction: Double) { onProgress(min(max(fraction, 0), 1)) }
}

// MARK: MP4 written with a chosen bitrate

enum MP4Writer {
    /// Reads the composed frames (and the mixed sound) and writes an H.264 / AAC MP4 at `bitrate`.
    static func write(asset: AVAsset, range: CMTimeRange, track: AVAssetTrack, composition: AVVideoComposition,
                      canvas: CGSize, bitrate: Int, hevc: Bool = false, audioTracks: [AVAssetTrack], audioMix: AVAudioMix?, control: ExportControl? = nil, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range

        let videoOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        videoOutput.videoComposition = composition
        reader.add(videoOutput)

        var audioOutput: AVAssetReaderAudioMixOutput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            ])
            output.audioMix = audioMix
            reader.add(output)
            audioOutput = output
        }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        writer.shouldOptimizeForNetworkUse = true
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: hevc ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
            AVVideoWidthKey: Int(canvas.width), AVVideoHeightKey: Int(canvas.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: 30,
                AVVideoMaxKeyFrameIntervalKey: 60,
            ].merging(hevc ? [:] : [AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel]) { a, _ in a },
        ])
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if audioOutput != nil {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 2, AVSampleRateKey: 44100, AVEncoderBitRateKey: 128_000,
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard reader.startReading(), writer.startWriting() else {
            throw reader.error ?? writer.error ?? ExportError.writeFailed
        }
        writer.startSession(atSourceTime: range.start)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let group = DispatchGroup()
            let total = max(range.duration.seconds, 0.001)
            func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderOutput, _ label: String) {
                group.enter()
                let queue = DispatchQueue(label: "melies.export.\(label)")
                input.requestMediaDataWhenReady(on: queue) {
                    while input.isReadyForMoreMediaData {
                        if control?.isCancelled == true {
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                        if let sample = output.copyNextSampleBuffer() {
                            // A refused sample means the writer failed (disk full, encoder error): stop, the status says why.
                            guard input.append(sample) else {
                                input.markAsFinished()
                                group.leave()
                                return
                            }
                            if label == "video" {
                                control?.report((CMSampleBufferGetPresentationTimeStamp(sample).seconds - range.start.seconds) / total)
                            }
                        } else {
                            input.markAsFinished()
                            group.leave()
                            return
                        }
                    }
                }
            }
            pump(videoInput, videoOutput, "video")
            if let audioInput, let audioOutput { pump(audioInput, audioOutput, "audio") }
            group.notify(queue: .global()) { continuation.resume() }
        }

        if control?.isCancelled == true {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw CancellationError()
        }
        // A failed read ends the loop like the end of the video: without this check the file would be truncated silently.
        if reader.status == .failed {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw reader.error ?? ExportError.writeFailed
        }
        await writer.finishWriting()
        if writer.status != .completed { throw writer.error ?? ExportError.writeFailed }
    }

    /// Read from the disk each time: `URL.resourceValues` caches, which made every retry see the first size.
    static func fileSize(_ url: URL) -> Int {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }
}

// MARK: GIF

enum GIFWriter {
    /// Writes an animated GIF, shrinking width and frame rate until it fits `maxMegabytes` (if any).
    static func write(asset: AVAsset, range: CMTimeRange, track: AVAssetTrack, composition: AVVideoComposition,
                      canvas: CGSize, maxMegabytes: Int?, control: ExportControl? = nil, to url: URL) async throws {
        let attempts: [(width: CGFloat, fps: Double)] = maxMegabytes == nil
            ? [(800, 15)]
            : [(720, 15), (600, 12), (480, 12), (400, 10), (320, 8), (256, 6), (200, 5), (160, 4), (128, 3)]
        for attempt in attempts {
            let width = min(attempt.width, canvas.width)
            let size = try await writeOnce(asset: asset, range: range, track: track, composition: composition,
                                           canvas: canvas, width: width, fps: attempt.fps, control: control, to: url)
            if let mb = maxMegabytes, size > mb * 1_000_000 { continue }
            return
        }
    }

    private static func writeOnce(asset: AVAsset, range: CMTimeRange, track: AVAssetTrack, composition: AVVideoComposition,
                                  canvas: CGSize, width: CGFloat, fps: Double, control: ExportControl?, to url: URL) async throws -> Int {
        try? FileManager.default.removeItem(at: url)
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [track], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        // The GIF keeps 3 to 15 frames per second: ask the compositor for just those instead of 30 and dropping most.
        if let gifComposition = composition.mutableCopy() as? AVMutableVideoComposition {
            gifComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps))
            output.videoComposition = gifComposition
        } else {
            output.videoComposition = composition
        }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? ExportError.writeFailed }

        let scale = width / canvas.width
        let seconds = range.duration.seconds
        let total = min(max(Int(seconds * fps), 1), 600)
        // The destination is open from the start and each frame is written as soon as it is drawn: a long GIF no
        // longer sits in memory as hundreds of full-size images before being encoded.
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, total, nil) else {
            throw ExportError.writeFailed
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFLoopCount as String: 0],
        ] as CFDictionary)
        let frameProperties = [kCGImagePropertyGIFDictionary as String: [kCGImagePropertyGIFDelayTime as String: 1 / fps]] as CFDictionary

        var last: CGImage?
        var written = 0
        while written < total, let sample = output.copyNextSampleBuffer() {
            if control?.isCancelled == true { reader.cancelReading(); throw CancellationError() }
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { continue }
            let image = CIImage(cvPixelBuffer: buffer).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            guard let cg = RenderContext.shared.createCGImage(image, from: image.extent) else { continue }
            CGImageDestinationAddImage(destination, cg, frameProperties)
            last = cg
            written += 1
            control?.report(Double(written) / Double(total))
        }
        guard let tail = last else { throw ExportError.noVideoTrack }
        while written < total { CGImageDestinationAddImage(destination, tail, frameProperties); written += 1 } // the source ended a little early
        guard CGImageDestinationFinalize(destination) else { throw ExportError.writeFailed }
        return MP4Writer.fileSize(url)
    }
}
