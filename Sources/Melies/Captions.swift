import Foundation

/// One recognized word with its time in the video (asset seconds). The speech engine only produces these.
struct CaptionWord: Equatable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

/// One subtitle line shown from `start` to `end` (asset seconds).
struct Caption: Identifiable, Equatable, Sendable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
}

struct CaptionStyle: Equatable, Sendable {
    enum Position: String, CaseIterable, Sendable { case bottom, top }
    enum Size: String, CaseIterable, Sendable {
        case small, medium, large
        /// Font size as a fraction of the picture width.
        var factor: Double {
            switch self {
            case .small: 0.020
            case .medium: 0.027
            case .large: 0.036
            }
        }
    }
    var position: Position = .bottom
    var size: Size = .medium
    var background = true
}

/// Pure helpers: grouping words into lines, trim handling, SRT. No speech engine involved, so all of it is testable.
enum CaptionLayout {
    static let maxLineChars = 42
    static let maxLines = 2
    static let maxDuration = 6.0
    /// A silence longer than this starts a new caption.
    static let pause = 0.8
    static let minDuration = 0.3

    /// Greedy word wrap. A word longer than `width` stays alone on its line.
    static func wrap(_ text: String, width: Int = maxLineChars) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if current.isEmpty { current = String(word) }
            else if current.count + 1 + word.count <= width { current += " " + word }
            else { lines.append(current); current = String(word) }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let last = text.last else { return false }
        return ".?!…".contains(last)
    }

    /// Groups timed words into captions of at most `maxLines` lines of `maxChars`, at most `maxDuration` seconds,
    /// split on pauses and after a finished sentence once the line has some length.
    static func group(_ words: [CaptionWord], maxChars: Int = maxLineChars, maxLines: Int = maxLines,
                      maxDuration: Double = maxDuration, pause: Double = pause) -> [Caption] {
        let clean = words
            .map { CaptionWord(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), start: $0.start, end: max($0.end, $0.start)) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
        var result: [Caption] = []
        var text = ""
        var start = 0.0, end = 0.0

        func flush() {
            guard !text.isEmpty else { return }
            result.append(Caption(start: start, end: max(end, start + minDuration), text: text))
            text = ""
        }

        for word in clean {
            if !text.isEmpty {
                let joined = text + " " + word.text
                let tooLong = wrap(joined, width: maxChars).count > maxLines
                let paused = word.start - end > pause
                let tooSlow = word.end - start > maxDuration
                let sentenceDone = endsSentence(text) && text.count >= maxChars / 2
                if tooLong || paused || tooSlow || sentenceDone { flush() }
            }
            if text.isEmpty { text = word.text; start = word.start } else { text += " " + word.text }
            end = word.end
        }
        flush()
        // A minimum display time must not run into the next caption.
        for i in result.indices.dropLast() where result[i].end > result[i + 1].start {
            result[i].end = max(result[i + 1].start, result[i].start)
        }
        return result
    }

    /// Keeps what overlaps [start, end] and cuts the edges. Captions that end up shorter than 0.1 s are dropped.
    static func clamp(_ captions: [Caption], start: Double, end: Double) -> [Caption] {
        captions.compactMap { c in
            var c = c
            c.start = max(c.start, start)
            c.end = min(c.end, end)
            return c.end - c.start >= 0.1 ? c : nil
        }
    }

    /// Moves every caption earlier by `offset` seconds (the trim start), never before 0.
    static func shifted(_ captions: [Caption], by offset: Double) -> [Caption] {
        captions.map { c in
            var c = c
            c.start = max(c.start - offset, 0)
            c.end = max(c.end - offset, 0)
            return c
        }
    }

    /// What the exported file contains for a trim range: clamped, then expressed from the start of the trim.
    static func forTrim(_ captions: [Caption], start: Double, end: Double) -> [Caption] {
        shifted(clamp(captions, start: start, end: end), by: start)
    }

    /// 00:00:01,250
    static func srtTimecode(_ seconds: Double) -> String {
        let ms = Int((max(seconds, 0) * 1000).rounded())
        return String(format: "%02d:%02d:%02d,%03d", ms / 3_600_000, ms / 60_000 % 60, ms / 1000 % 60, ms % 1000)
    }

    static func srt(_ captions: [Caption]) -> String {
        captions.enumerated().map { i, c in
            "\(i + 1)\n\(srtTimecode(c.start)) --> \(srtTimecode(c.end))\n\(wrap(c.text).joined(separator: "\n"))\n"
        }.joined(separator: "\n")
    }

    /// The caption shown at `time`, if any.
    static func visible(_ captions: [Caption], at time: Double) -> Caption? {
        captions.first { time >= $0.start - 0.0001 && time <= $0.end + 0.0001 }
    }
}

/// What the export needs: the lines and how to draw them. Value type, safe to hand to the compositor.
struct CaptionPlan: Sendable {
    var captions: [Caption]
    var style: CaptionStyle
}
