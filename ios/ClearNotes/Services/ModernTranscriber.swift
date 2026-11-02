#if compiler(>=6.2)
import AVFoundation
import CoreMedia
import Speech

/// Transcription with iOS 26's SpeechAnalyzer and SpeechTranscriber.
///
/// Apple built this model for long-form, distant speech such as meetings, so it handles
/// people across the table far better than the older recogniser. It runs entirely on the
/// iPhone and reports finished sentences with their times, so no chunk restarting is needed.
@available(iOS 26.0, *)
final class ModernTranscriber: @unchecked Sendable {
    struct Update: Sendable {
        var finalized: TranscriptSegment?
        var volatileText: String
    }

    private let transcriber: SpeechTranscriber
    private let analyzer: SpeechAnalyzer
    private let analyzerFormat: AVAudioFormat
    private let inputStream: AsyncStream<AnalyzerInput>
    private let input: AsyncStream<AnalyzerInput>.Continuation
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var resultsTask: Task<Void, Never>?

    /// Returns nil when this iPhone or language can't use the new model, so the caller
    /// can fall back to the older recogniser.
    static func make(locale: Locale) async -> ModernTranscriber? {
        let supported = await SpeechTranscriber.supportedLocales
        let wanted = locale.identifier(.bcp47)
        let language = locale.language.languageCode
        guard let match = supported.first(where: { $0.identifier(.bcp47) == wanted })
            ?? supported.first(where: { $0.language.languageCode == language })
        else { return nil }

        let transcriber = SpeechTranscriber(
            locale: match,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange]
        )
        do {
            // Downloads the language model once if it isn't already on the iPhone.
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
        } catch {
            return nil
        }
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            return nil
        }
        return ModernTranscriber(transcriber: transcriber, format: format)
    }

    private init(transcriber: SpeechTranscriber, format: AVAudioFormat) {
        self.transcriber = transcriber
        self.analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzerFormat = format
        (inputStream, input) = AsyncStream<AnalyzerInput>.makeStream()
    }

    func start(onUpdate: @escaping @Sendable (Update) -> Void) async throws {
        let transcriber = transcriber
        resultsTask = Task {
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if result.isFinal {
                        let segment = text.isEmpty ? nil : TranscriptSegment(
                            start: result.range.start.seconds,
                            end: result.range.end.seconds,
                            text: text
                        )
                        onUpdate(Update(finalized: segment, volatileText: ""))
                    } else {
                        onUpdate(Update(finalized: nil, volatileText: text))
                    }
                }
            } catch {
                // The stream ends with an error if transcription is cancelled; nothing to do.
            }
        }
        try await analyzer.start(inputSequence: inputStream)
    }

    /// Called on the audio thread with microphone buffers.
    func append(_ buffer: AVAudioPCMBuffer) {
        if buffer.format == analyzerFormat {
            input.yield(AnalyzerInput(buffer: buffer))
            return
        }
        lock.lock()
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
        }
        let converter = converter
        lock.unlock()
        guard let converter else { return }

        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: capacity) else { return }
        final class Once: @unchecked Sendable { var supplied = false }
        let once = Once()
        var error: NSError?
        _ = converter.convert(to: output, error: &error) { _, status in
            if once.supplied {
                status.pointee = .noDataNow
                return nil
            }
            once.supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil && output.frameLength > 0 {
            input.yield(AnalyzerInput(buffer: output))
        }
    }

    /// Ends the audio and waits (briefly) for the last sentences.
    func finish() async {
        input.finish()
        try? await analyzer.finalizeAndFinishThroughEndOfInput()
        let results = resultsTask
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await results?.value }
            group.addTask { try? await Task.sleep(for: .seconds(4)) }
            await group.next()
            group.cancelAll()
        }
        resultsTask?.cancel()
    }

    /// Stops without waiting for the remaining results.
    func cancel() {
        input.finish()
        resultsTask?.cancel()
        let analyzer = analyzer
        Task { try? await analyzer.finalizeAndFinishThroughEndOfInput() }
    }
}
#endif
