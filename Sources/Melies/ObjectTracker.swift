import AVFoundation

/// Follows a region of the video (scrolling text, a moving window, a face...) by matching its pixels
/// image after image. When the region can no longer be found (scrolled out, covered by something),
/// tracking stops and reports when.
/// Positions are normalized in the upright frame (origin top left), the same space as annotations.
enum ObjectTracker {
    struct Result {
        var samples: [TrackSample]
        /// When the region was lost before `to`, nil if it was followed to the end.
        var lostAt: Double?
        var lost: Bool { lostAt != nil }
    }

    /// Mean luma difference, relative to the contrast of the region, above which it is considered gone
    /// (about 0 for a perfect match, about 1.1 for unrelated content).
    private static let lostThreshold = 0.5

    private struct Luma {
        var width: Int, height: Int
        var data: [UInt8]
    }

    /// Tracks `box` (normalized, origin top left) found in the frame at `from`.
    /// `progress` is called with 0...1 from a background queue. Throws CancellationError when cancelled.
    static func track(
        asset: AVAsset, box: CGRect, from: Double, to: Double,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> Result {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { return Result(samples: [], lostAt: nil) }
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
        defer { reader.cancelReading() }

        var template: [Float] = []
        var tw = 0, th = 0, originX = 0, originY = 0
        var x = 0, y = 0
        var samples: [TrackSample] = []
        var badSince: Double?
        let span = max(to - from, 0.001)

        while let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            guard let pixels = CMSampleBufferGetImageBuffer(buffer), let frame = luma(of: pixels) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds

            if template.isEmpty {
                originX = Int((box.minX * Double(frame.width)).rounded())
                originY = Int((box.minY * Double(frame.height)).rounded())
                tw = max(min(Int((box.width * Double(frame.width)).rounded()), frame.width - originX), 4)
                th = max(min(Int((box.height * Double(frame.height)).rounded()), frame.height - originY), 4)
                template = patch(of: frame, x: originX, y: originY, w: tw, h: th)
                x = originX; y = originY
                samples.append(TrackSample(t: t, dx: 0, dy: 0))
                continue
            }

            let (bx, by, score) = bestMatch(of: template, tw: tw, th: th, in: frame, around: (x, y))
            // Touching a frame edge it was not on at the start means it is leaving the frame.
            let leaving = (bx <= 0 && originX > 0) || (by <= 0 && originY > 0)
                || (bx >= frame.width - tw && originX < frame.width - tw)
                || (by >= frame.height - th && originY < frame.height - th)
            if score > lostThreshold || leaving {
                // Tolerate a couple of noisy frames (a flash, a compression glitch) before giving up.
                if badSince == nil { badSince = t }
                if t - (badSince ?? t) > 0.12 { return Result(samples: samples, lostAt: badSince) }
                continue
            }
            badSince = nil
            x = bx; y = by
            // Follow slow appearance changes without drifting away from the original look.
            if score < lostThreshold * 0.3 {
                let now = patch(of: frame, x: x, y: y, w: tw, h: th)
                for i in template.indices { template[i] += (now[i] - template[i]) * 0.08 }
            }
            samples.append(TrackSample(
                t: t,
                dx: Double(x - originX) / Double(frame.width),
                dy: Double(y - originY) / Double(frame.height)
            ))
            progress(min(max((t - from) / span, 0), 1))
        }
        return Result(samples: samples, lostAt: nil)
    }

    /// Grayscale copy of the frame, at most ~640 px wide so matching stays fast.
    private static func luma(of buffer: CVPixelBuffer) -> Luma? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let f = max(1, Int((Double(w) / 640).rounded()))
        let ow = w / f, oh = h / f
        var data = [UInt8](repeating: 0, count: ow * oh)
        let src = base.assumingMemoryBound(to: UInt8.self)
        for j in 0..<oh {
            let row = src + j * f * stride
            for i in 0..<ow {
                let p = row + i * f * 4 // BGRA
                data[j * ow + i] = UInt8((Int(p[0]) * 29 + Int(p[1]) * 150 + Int(p[2]) * 77) >> 8)
            }
        }
        return Luma(width: ow, height: oh, data: data)
    }

    private static func patch(of frame: Luma, x: Int, y: Int, w: Int, h: Int) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        for j in 0..<h { for i in 0..<w { out[j * w + i] = Float(frame.data[(y + j) * frame.width + x + i]) } }
        return out
    }

    /// Where the template fits best in the frame, searching around the last position (coarse, then fine).
    /// Returns the top-left position and the difference relative to the region's contrast.
    private static func bestMatch(of template: [Float], tw: Int, th: Int, in frame: Luma, around p: (Int, Int)) -> (Int, Int, Double) {
        let maxX = frame.width - tw, maxY = frame.height - th
        guard maxX >= 0, maxY >= 0 else { return (p.0, p.1, 9) }
        let radiusX = max(frame.width / 8, 12), radiusY = max(frame.height / 6, 12)
        let sampleStep = max(1, Int(Double(tw * th).squareRoot() / 28))
        // Differences are judged against how much the region itself varies, so a plain area is not "matched" by chance.
        let mean = template.reduce(0, +) / Float(template.count)
        let contrast = Double(template.reduce(0) { $0 + abs($1 - mean) } / Float(template.count))
        let denom = max(contrast, 8)

        func cost(_ ox: Int, _ oy: Int, step: Int, stop: Double) -> Double {
            var sum: Double = 0, count = 0
            var j = 0
            while j < th {
                let rowT = j * tw, rowF = (oy + j) * frame.width + ox
                var i = 0
                while i < tw {
                    sum += Double(abs(template[rowT + i] - Float(frame.data[rowF + i])))
                    count += 1
                    i += step
                }
                if sum / (Double(count) * denom) > stop { return 9 }
                j += step
            }
            return sum / (Double(max(count, 1)) * denom)
        }

        var best = (x: min(max(p.0, 0), maxX), y: min(max(p.1, 0), maxY), score: 9.0)
        best.score = cost(best.x, best.y, step: sampleStep, stop: 9)
        let coarse = 2
        var oy = max(p.1 - radiusY, 0)
        while oy <= min(p.1 + radiusY, maxY) {
            var ox = max(p.0 - radiusX, 0)
            while ox <= min(p.0 + radiusX, maxX) {
                let c = cost(ox, oy, step: sampleStep, stop: best.score)
                if c < best.score { best = (ox, oy, c) }
                ox += coarse
            }
            oy += coarse
        }
        // Fine pass around the coarse winner, with every pixel of the template (every 2nd for big ones).
        let fineStep = max(1, sampleStep / 2)
        var fine = best
        for oy in max(best.y - coarse, 0)...min(best.y + coarse, maxY) {
            for ox in max(best.x - coarse, 0)...min(best.x + coarse, maxX) {
                let c = cost(ox, oy, step: fineStep, stop: fine.score)
                if c < fine.score { fine = (ox, oy, c) }
            }
        }
        return (fine.x, fine.y, fine.score)
    }
}
