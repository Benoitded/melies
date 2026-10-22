import AVFoundation
import Speech

enum CaptionError: LocalizedError, Equatable {
    case noAudio
    case permissionDenied
    case unsupported
    case languageUnavailable
    case noSpeech
    case failed

    var errorDescription: String? {
        switch self {
        case .noAudio: L("cap.err.noaudio")
        case .permissionDenied: L("cap.err.permission")
        case .unsupported: L("cap.err.unsupported")
        case .languageUnavailable: L("cap.err.language")
        case .noSpeech: L("cap.err.nospeech")
        case .failed: L("cap.err.failed")
        }
    }
}

extension CaptionLayout {
    /// Splits one recognized piece of text (a run can hold several words) into words, sharing the time by length.
    static func words(from piece: String, start: Double, end: Double) -> [CaptionWord] {
        let parts = piece.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        let total = parts.reduce(0) { $0 + $1.count }
        guard total > 0 else { return [] }
        let span = max(end - start, 0)
        var cursor = start
        return parts.map { part in
            let length = span * Double(part.count) / Double(total)
            defer { cursor += length }
            return CaptionWord(text: part, start: cursor, end: cursor + length)
        }
    }
}

/// On-device captions: the audio is read from the video and given to the Speech framework's `SpeechTranscriber`
/// (macOS 26). Nothing is sent anywhere: only language models already installed on the Mac are used, and a model that
/// is not installed is reported instead of being downloaded.
enum CaptionGenerator {
    /// Locales whose on-device model is installed, sorted by name.
    static func installedLocales() async -> [Locale] {
        guard SpeechTranscriber.isAvailable else { return [] }
        let locales = await SpeechTranscriber.installedLocales
        var seen = Set<String>()
        return locales.filter { seen.insert($0.identifier).inserted }
            .sorted { name($0) < name($1) }
    }

    static func name(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// The installed locale that matches the app language (or the system language), if any.
    static func defaultLocale(among installed: [Locale], preferred: [String] = Bundle.main.preferredLocalizations + Locale.preferredLanguages) -> Locale? {
        for tag in preferred {
            let language = Locale(identifier: tag).language.languageCode?.identifier ?? tag
            if let match = installed.first(where: { $0.language.languageCode?.identifier == language }) { return match }
        }
        return installed.first
    }

    private static func requireAuthorization() async throws {
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        guard status == .authorized else { throw CaptionError.permissionDenied }
    }

    /// Recognizes the speech of the whole audio. `progress` is 0...1. Cancelling the task stops the work.
    static func generate(asset: AVAsset, locale: Locale, progress: @escaping @Sendable (Double) -> Void) async throws -> [CaptionWord] {
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw CaptionError.noAudio }
        guard SpeechTranscriber.isAvailable else { throw CaptionError.unsupported }
        try await requireAuthorization()

        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else { throw CaptionError.languageUnavailable }
        let transcriber = SpeechTranscriber(locale: supported, transcriptionOptions: [], reportingOptions: [], attributeOptions: [.audioTimeRange])
        guard await AssetInventory.status(forModules: [transcriber]) >= .installed else { throw CaptionError.languageUnavailable }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { throw CaptionError.failed }

        let duration = max(try await asset.load(.duration).seconds, 0.001)
        let reader = try AVAssetReader(asset: asset)
        let float = format.commonFormat == .pcmFormatFloat32
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: float ? 32 : 16,
            AVLinearPCMIsFloatKey: float,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        guard reader.canAdd(output) else { throw CaptionError.failed }
        reader.add(output)
        guard reader.startReading() else { throw CaptionError.failed }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let (inputs, continuation) = AsyncStream<AnalyzerInput>.makeStream()

        let collector = Task { () -> [CaptionWord] in
            var words: [CaptionWord] = []
            for try await result in transcriber.results where result.isFinal {
                for run in result.text.runs {
                    let piece = String(result.text[run.range].characters)
                    let range = run.audioTimeRange ?? result.range
                    words += CaptionLayout.words(from: piece, start: range.start.seconds, end: range.end.seconds)
                }
            }
            return words
        }
        let feeder = Task.detached { () -> Void in
            while !Task.isCancelled, reader.status == .reading, let sample = output.copyNextSampleBuffer() {
                guard let description = CMSampleBufferGetFormatDescription(sample),
                      let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
                      let bufferFormat = AVAudioFormat(streamDescription: asbd) else { continue }
                let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
                guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: bufferFormat, frameCapacity: frames) else { continue }
                buffer.frameLength = frames
                guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else { continue }
                let time = CMSampleBufferGetPresentationTimeStamp(sample)
                continuation.yield(AnalyzerInput(buffer: buffer, bufferStartTime: time))
                progress(min(max(time.seconds / duration, 0), 1) * 0.9)
            }
            if reader.status == .reading { reader.cancelReading() }
            continuation.finish()
        }

        return try await withTaskCancellationHandler {
            do {
                try await analyzer.start(inputSequence: inputs)
                await feeder.value
                try Task.checkCancellation()
                try await analyzer.finalizeAndFinishThroughEndOfInput()
                let words = try await collector.value
                progress(1)
                guard !words.isEmpty else { throw CaptionError.noSpeech }
                return words
            } catch let error as CaptionError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw CaptionError.failed
            }
        } onCancel: {
            feeder.cancel()
            collector.cancel()
            continuation.finish()
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}
