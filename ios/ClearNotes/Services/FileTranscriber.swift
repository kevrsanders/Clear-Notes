import AVFoundation
import Foundation
import Speech

/// Transcribes a finished recording from its audio file, on the iPhone. Used for recordings made
/// on Apple Watch, which arrive without a live transcript.
///
/// Uses the more accurate Parakeet model when it's downloaded, else Apple's SpeechAnalyzer on
/// iOS 26, else the older on-device speech recogniser.
enum FileTranscriber {
    enum Outcome {
        /// `improved` when it came from the more accurate model, so that pass isn't run again.
        case transcribed([TranscriptSegment], improved: Bool)
        /// The recording can't be read while the iPhone is locked.
        case locked
        case failed(String)
    }

    @MainActor
    static func transcribe(_ url: URL) async -> Outcome {
        guard AppActivity.isUnlocked else { return .locked }
        var lastError: Error?

        if AccurateTranscriber.isReady {
            do {
                let words = try await AccurateTranscriber.shared.words(in: url)
                let segments = TranscriptBuilder.segments(from: words)
                if !segments.isEmpty { return .transcribed(segments, improved: true) }
            } catch {
                if AppActivity.isLockedFileError(error) || !AppActivity.isUnlocked { return .locked }
                lastError = error
            }
        }

        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            do {
                if let segments = try await modernSegments(in: url), !segments.isEmpty {
                    return .transcribed(segments, improved: false)
                }
            } catch {
                if AppActivity.isLockedFileError(error) || !AppActivity.isUnlocked { return .locked }
                lastError = error
            }
        }
        #endif

        do {
            let segments = try await recogniserSegments(in: url)
            if !segments.isEmpty { return .transcribed(segments, improved: false) }
        } catch {
            if AppActivity.isLockedFileError(error) || !AppActivity.isUnlocked { return .locked }
            lastError = error
        }

        if let lastError {
            return .failed("The recording couldn't be transcribed. \(lastError.localizedDescription)")
        }
        return .failed("No speech was found in this recording.")
    }

    // MARK: - iOS 26: SpeechAnalyzer

    #if compiler(>=6.2)
    /// Feeds the file through the same SpeechAnalyzer transcriber used while recording.
    @available(iOS 26.0, *)
    private static func modernSegments(in url: URL) async throws -> [TranscriptSegment]? {
        guard let transcriber = await ModernTranscriber.make(locale: .current) else { return nil }
        let collected = SegmentCollector()
        try await transcriber.start { update in
            if let segment = update.finalized { collected.add(segment) }
        }
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        while file.framePosition < file.length {
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_384) else { break }
            try file.read(into: buffer)
            if buffer.frameLength == 0 { break }
            transcriber.append(buffer)
            await Task.yield()
        }
        await transcriber.finish()
        return collected.segments
    }
    #endif

    // MARK: - Earlier iOS: the on-device speech recogniser

    private static func recogniserSegments(in url: URL) async throws -> [TranscriptSegment] {
        guard let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer() else { return [] }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        let words: [TimedWord] = try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce()
            _ = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    if once.claim() { continuation.resume(throwing: error) }
                    return
                }
                guard let result, result.isFinal else { return }
                let words = result.bestTranscription.segments.map {
                    TimedWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
                }
                if once.claim() { continuation.resume(returning: words) }
            }
        }
        return TranscriptBuilder.segments(from: words)
    }
}

/// Finished lines from the transcriber, which reports them on its own task.
private final class SegmentCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [TranscriptSegment] = []

    func add(_ segment: TranscriptSegment) {
        lock.lock()
        collected.append(segment)
        lock.unlock()
    }

    var segments: [TranscriptSegment] {
        lock.lock()
        defer { lock.unlock() }
        return collected.sorted { $0.start < $1.start }
    }
}

/// Makes sure a continuation is resumed only once.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
