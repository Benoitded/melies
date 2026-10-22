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
        var offscreen = false
        /// When tracking backward: the earlier moment where the object was lost (it was not visible before it).
        var startAt: Double?
        var lost: Bool { lostAt != nil }
    }

    /// MELIES_TRACK_DEBUG=1 prints every match to stderr. Read once: it used to copy the whole environment at every frame.
    private static let debugTrace: Bool = {
        #if DEBUG || MELIES_HOOKS
        return ProcessInfo.processInfo.environment["MELIES_TRACK_DEBUG"] != nil
        #else
        return false
        #endif
    }()

    /// Mean luma difference, relative to the contrast of the region, above which it is considered gone
    /// (about 0 for a perfect match, about 1.1 for unrelated content).
    private static let lostThreshold = 0.5

    private struct Luma {
        var width: Int, height: Int
        var data: [UInt8]
    }

    /// The state of one pass of the tracker: the region as it looked, where it is now, how it was moving.
    /// One walker goes forward in time from the reference frame, another goes backward.
    private struct Walker {
        var template: [Float] = []
        var templateBlur: [Float] = []
        var tw = 0, th = 0, originX = 0, originY = 0
        var x = 0, y = 0
        var vx = 0, vy = 0 // last movement per frame, to look where a fast scroll is going
        var badSince: Double?
        var badOffscreen = false

        enum Step { case reference(TrackSample), sample(TrackSample), skipped, lost(at: Double, offscreen: Bool) }

        mutating func step(box: CGRect, frame: Luma, t: Double) -> Step {
            let soft = blurred(frame)
            if template.isEmpty {
                originX = Int((box.minX * Double(frame.width)).rounded())
                originY = Int((box.minY * Double(frame.height)).rounded())
                tw = max(min(Int((box.width * Double(frame.width)).rounded()), frame.width - originX), 4)
                th = max(min(Int((box.height * Double(frame.height)).rounded()), frame.height - originY), 4)
                // A box ending within 4 px of an edge was widened to 4: pull it back inside so no read goes past the image.
                originX = max(min(originX, frame.width - tw), 0)
                originY = max(min(originY, frame.height - th), 0)
                template = patch(of: frame, x: originX, y: originY, w: tw, h: th)
                templateBlur = patch(of: soft, x: originX, y: originY, w: tw, h: th)
                x = originX; y = originY
                return .reference(TrackSample(t: t, dx: 0, dy: 0))
            }

            let (bx, by, score) = bestMatch(of: template, blurTemplate: templateBlur, tw: tw, th: th, in: frame, blurFrame: soft, around: (x + vx, y + vy))
            if debugTrace { FileHandle.standardError.write(Data("t=\(String(format: "%.3f", t)) pos=(\(bx),\(by)) from=(\(x),\(y)) score=\(String(format: "%.2f", score)) frame=\(frame.width)x\(frame.height)\n".utf8)) }
            // Touching a frame edge it was not on at the start means it is leaving the frame.
            let leaving = (bx <= 0 && originX > 0) || (by <= 0 && originY > 0)
                || (bx >= frame.width - tw && originX < frame.width - tw)
                || (by >= frame.height - th && originY < frame.height - th)
            if score > lostThreshold || leaving {
                // Tolerate a couple of noisy frames (a flash, a compression glitch) before giving up.
                if badSince == nil { badSince = t; badOffscreen = leaving }
                if abs(t - (badSince ?? t)) > 0.12 { return .lost(at: badSince ?? t, offscreen: badOffscreen) }
                return .skipped
            }
            badSince = nil
            vx = bx - x; vy = by - y
            x = bx; y = by
            // Follow slow appearance changes without drifting away from the original look.
            if score < lostThreshold * 0.3 {
                let now = patch(of: frame, x: x, y: y, w: tw, h: th)
                let nowBlur = patch(of: soft, x: x, y: y, w: tw, h: th)
                for i in template.indices {
                    template[i] += (now[i] - template[i]) * 0.08
                    templateBlur[i] += (nowBlur[i] - templateBlur[i]) * 0.08
                }
            }
            return .sample(TrackSample(t: t, dx: Double(x - originX) / Double(frame.width), dy: Double(y - originY) / Double(frame.height)))
        }
    }

    /// Tracks `box` (normalized, origin top left) found in the frame at `from`, forward until `to` and, when
    /// `lowerBound` is earlier than `from`, backward until `lowerBound`: a tracking started in the middle of an
    /// annotation must follow the object on both sides of that frame.
    /// `progress` is called with 0...1 from a background queue. Throws CancellationError when cancelled.
    static func track(
        asset: AVAsset, box: CGRect, from: Double, to: Double, lowerBound: Double? = nil,
        progress: @escaping @Sendable (Double) -> Void,
        onSample: (@Sendable (TrackSample) -> Void)? = nil
    ) async throws -> Result {
        guard let video = try await asset.loadTracks(withMediaType: .video).first else { return Result(samples: [], lostAt: nil) }
        let composition = try await AVMutableVideoComposition.videoComposition(withPropertiesOf: asset)
        let before = max(from - (lowerBound ?? from), 0)
        let after = max(to - from, 0.001)
        let forwardShare = after / (after + before)

        func reader(for range: CMTimeRange) throws -> (AVAssetReader, AVAssetReaderVideoCompositionOutput) {
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderVideoCompositionOutput(videoTracks: [video], videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
            output.videoComposition = composition
            reader.add(output)
            reader.timeRange = range
            guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
            return (reader, output)
        }
        func seconds(_ t: Double) -> CMTime { CMTime(seconds: t, preferredTimescale: 600) }

        // Forward pass: frames are read and matched one by one.
        var forward: [TrackSample] = []
        var lostAt: Double?
        var lostOffscreen = false
        do {
            let (reader, output) = try reader(for: CMTimeRange(start: seconds(from), end: seconds(to)))
            defer { reader.cancelReading() }
            var walker = Walker()
            while let buffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let pixels = CMSampleBufferGetImageBuffer(buffer), let frame = luma(of: pixels) else { continue }
                let t = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                switch walker.step(box: box, frame: frame, t: t) {
                case .reference(let sample), .sample(let sample):
                    forward.append(sample)
                    onSample?(sample)
                    progress(min(max((t - from) / after, 0), 1) * forwardShare)
                case .skipped: continue
                case .lost(let at, let offscreen): lostAt = at; lostOffscreen = offscreen
                }
                if lostAt != nil { break }
            }
        }

        // Backward pass: a reader cannot play backward, so the frames before `from` are read first (kept small,
        // and thinned when there are very many), then walked from the reference frame back in time.
        var backward: [TrackSample] = []
        var startAt: Double?
        if let lowerBound, before > 0.05 {
            var frames: [(t: Double, frame: Luma)] = []
            // Decimate while reading (a 10 min 60 fps stretch would otherwise hold gigabytes): keep about 400
            // frames, every thin-th one plus always the last (the reference at `from`).
            let fps = max(Double((try? await video.load(.nominalFrameRate)) ?? 60), 1)
            let thin = max(1, Int((before * fps / 400).rounded(.up)))
            let (reader, output) = try reader(for: CMTimeRange(start: seconds(lowerBound), end: seconds(from + 0.001)))
            defer { reader.cancelReading() }
            var index = 0
            var pending: (t: Double, frame: Luma)?
            while let buffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                guard let pixels = CMSampleBufferGetImageBuffer(buffer), let frame = luma(of: pixels) else { continue }
                let item = (t: CMSampleBufferGetPresentationTimeStamp(buffer).seconds, frame: frame)
                if index % thin == 0 { frames.append(item); pending = nil } else { pending = item }
                index += 1
            }
            if let pending { frames.append(pending) }
            var walker = Walker()
            for (t, frame) in frames.reversed() {
                try Task.checkCancellation()
                switch walker.step(box: box, frame: frame, t: t) {
                case .reference: continue // the same reference sample as the forward pass
                case .sample(let sample):
                    backward.append(sample)
                    onSample?(sample)
                    progress(forwardShare + min(max((from - t) / before, 0), 1) * (1 - forwardShare))
                case .skipped: continue
                case .lost(let at, _): startAt = at
                }
                if startAt != nil { break }
            }
        }

        return Result(samples: backward.reversed() + forward, lostAt: lostAt, offscreen: lostOffscreen, startAt: startAt)
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
        // Average each f x f block: picking one pixel in f would alias thin text and break matching on scrolls.
        let area = f * f
        for j in 0..<oh {
            for i in 0..<ow {
                var sum = 0
                for dj in 0..<f {
                    let row = src + (j * f + dj) * stride + i * f * 4
                    for di in 0..<f {
                        let p = row + di * 4 // BGRA
                        sum += (Int(p[0]) * 29 + Int(p[1]) * 150 + Int(p[2]) * 77) >> 8
                    }
                }
                data[j * ow + i] = UInt8(sum / area)
            }
        }
        return Luma(width: ow, height: oh, data: data)
    }

    /// A softened copy (box blur, radius 3): on fine text the sharp match is a 1 px wide dip, so the coarse
    /// search runs on this one, where the dip is wide enough not to be stepped over.
    private static func blurred(_ frame: Luma) -> Luma {
        let r = 3, w = frame.width, h = frame.height
        var tmp = [Float](repeating: 0, count: w * h)
        var out = [UInt8](repeating: 0, count: w * h)
        for j in 0..<h {
            for i in 0..<w {
                var sum: Float = 0
                for k in -r...r { sum += Float(frame.data[j * w + min(max(i + k, 0), w - 1)]) }
                tmp[j * w + i] = sum / Float(2 * r + 1)
            }
        }
        for j in 0..<h {
            for i in 0..<w {
                var sum: Float = 0
                for k in -r...r { sum += tmp[min(max(j + k, 0), h - 1) * w + i] }
                out[j * w + i] = UInt8(sum / Float(2 * r + 1))
            }
        }
        return Luma(width: w, height: h, data: out)
    }

    private static func patch(of frame: Luma, x: Int, y: Int, w: Int, h: Int) -> [Float] {
        var out = [Float](repeating: 0, count: w * h)
        for j in 0..<h { for i in 0..<w { out[j * w + i] = Float(frame.data[(y + j) * frame.width + x + i]) } }
        return out
    }

    /// Where the template fits best in the frame, searching around the predicted position:
    /// coarse on the blurred images, then fine on the sharp ones.
    /// Returns the top-left position and the difference relative to the region's contrast.
    private static func bestMatch(of template: [Float], blurTemplate: [Float], tw: Int, th: Int, in frame: Luma, blurFrame: Luma,
                                  around p: (Int, Int)) -> (Int, Int, Double) {
        let maxX = frame.width - tw, maxY = frame.height - th
        guard maxX >= 0, maxY >= 0 else { return (p.0, p.1, 9) }
        let radiusX = max(frame.width / 6, 12), radiusY = max(frame.height / 3, 12)
        let sampleStep = max(1, Int(Double(tw * th).squareRoot() / 28))
        // Differences are judged against how much the region itself varies, so a plain area is not "matched" by chance.
        let mean = template.reduce(0, +) / Float(template.count)
        let contrast = Double(template.reduce(0) { $0 + abs($1 - mean) } / Float(template.count))
        let denom = max(contrast, 8)

        func cost(_ t: [Float], _ f: Luma, _ ox: Int, _ oy: Int, step: Int, stop: Double) -> Double {
            var sum: Double = 0, count = 0
            var j = 0
            while j < th {
                let rowT = j * tw, rowF = (oy + j) * f.width + ox
                var i = 0
                while i < tw {
                    sum += Double(abs(t[rowT + i] - Float(f.data[rowF + i])))
                    count += 1
                    i += step
                }
                if sum / (Double(count) * denom) > stop { return 9 }
                j += step
            }
            return sum / (Double(max(count, 1)) * denom)
        }

        let cx = min(max(p.0, 0), maxX), cy = min(max(p.1, 0), maxY)
        var best = (x: cx, y: cy, score: cost(blurTemplate, blurFrame, cx, cy, step: sampleStep, stop: 9))
        let coarse = 3
        var oy = max(cy - radiusY, 0)
        while oy <= min(cy + radiusY, maxY) {
            var ox = max(cx - radiusX, 0)
            while ox <= min(cx + radiusX, maxX) {
                let c = cost(blurTemplate, blurFrame, ox, oy, step: sampleStep, stop: best.score)
                if c < best.score { best = (ox, oy, c) }
                ox += coarse
            }
            oy += coarse
        }
        // Fine pass on the sharp images around the coarse winner (and the unmoved position, in case nothing moved).
        var fine = (x: best.x, y: best.y, score: 9.0)
        for centre in [(best.x, best.y), (cx, cy)] {
            for oy in max(centre.1 - coarse, 0)...min(centre.1 + coarse, maxY) {
                for ox in max(centre.0 - coarse, 0)...min(centre.0 + coarse, maxX) {
                    let c = cost(template, frame, ox, oy, step: max(1, sampleStep / 2), stop: fine.score)
                    if c < fine.score { fine = (ox, oy, c) }
                }
            }
        }
        return (fine.x, fine.y, fine.score)
    }
}
