import AVFoundation
import Vision

/// Follows a region of the video with Apple's Vision tracker, from `from` to `to` seconds.
/// Positions are normalized in the upright frame (origin top left), the same space as annotations.
enum ObjectTracker {
    struct Result {
        var samples: [TrackSample]
        /// True when the object was lost before `to`: the last sample is held from then on.
        var lost: Bool
    }

    /// Tracks `box` (normalized, origin top left) found in the frame at `from`.
    /// `progress` is called with 0...1 from a background queue. Throws CancellationError when cancelled.
    static func track(
        asset: AVAsset, box: CGRect, from: Double, to: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Result {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { return Result(samples: [], lost: false) }
        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [video],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        )
        output.videoComposition = composition
        reader.add(output)
        reader.timeRange = CMTimeRange(start: CMTime(seconds: from, preferredTimescale: 600),
                                       end: CMTime(seconds: to, preferredTimescale: 600))
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }

        // Vision uses a bottom-left origin.
        let visionBox = CGRect(x: box.minX, y: 1 - box.maxY, width: box.width, height: box.height)
        var observation = VNDetectedObjectObservation(boundingBox: visionBox)
        let handler = VNSequenceRequestHandler()
        var samples: [TrackSample] = []
        var lost = false
        let span = max(to - from, 0.001)

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixels = CMSampleBufferGetImageBuffer(buffer) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
            let request = VNTrackObjectRequest(detectedObjectObservation: observation)
            request.trackingLevel = .accurate
            try handler.perform([request], on: pixels)
            guard let result = request.results?.first as? VNDetectedObjectObservation, result.confidence > 0.2 else {
                lost = true
                break
            }
            observation = result
            // Offsets of the box centre relative to the start, y flipped back to top-left.
            samples.append(TrackSample(
                t: t,
                dx: Double(result.boundingBox.midX - visionBox.midX),
                dy: -Double(result.boundingBox.midY - visionBox.midY)
            ))
            progress(min(max((t - from) / span, 0), 1))
        }
        reader.cancelReading()
        return Result(samples: samples, lost: lost)
    }
}
