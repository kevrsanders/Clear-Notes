import AVFoundation
import Observation
import Speech

struct RecordingResult {
    var duration: TimeInterval
    var segments: [TranscriptSegment]
    /// Temporary audio for speaker separation, if it was captured.
    var audioFileName: String?
    /// Moments marked as actions or decisions while recording.
    var marks: [MeetingMark] = []
    /// How many people the user said are in the meeting, or nil for Auto.
    var expectedSpeakers: Int?
}

enum RecorderError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case onDeviceUnsupported
    case noMicrophone

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            "Clear Notes needs microphone and speech recognition access. You can turn these on in Settings."
        case .recognizerUnavailable:
            "Speech recognition isn't available right now. Check your language settings and try again."
        case .onDeviceUnsupported:
            "On-device transcription isn't supported for your language on this iPhone. You can allow Apple's servers in Clear Notes settings."
        case .noMicrophone:
            "No microphone input was found."
        }
    }
}

/// Captures microphone audio and transcribes it live.
///
/// On iOS 26 it uses SpeechAnalyzer (`ModernTranscriber`), Apple's long-form model that copes
/// with people sitting further from the iPhone. On older versions it uses SFSpeechRecognizer in
/// short chunks: a chunk ends at a natural pause (or after `maxChunkLength`) and becomes a
/// timestamped segment, which keeps long meetings going.
///
/// Quiet audio is boosted before transcription so voices across a table are easier to hear.
/// When speaker identification is on, a 16 kHz mono copy of the audio is written to a
/// temporary file for speaker separation. It is deleted once speakers are identified.
@MainActor
@Observable
final class MeetingRecorder {
    enum State: Equatable {
        case idle, recording, paused, stopping
    }

    /// One recognition request in the older engine. The recogniser can start its text afresh
    /// after a pause, so finished utterances are kept in `committed` and joined with `current`.
    private struct Chunk {
        var start: TimeInterval
        var end: TimeInterval?
        var committed = ""
        var committedWords: [TimedWord] = []
        var current = ""
        var currentWords: [TimedWord] = []

        var text: String { TranscriptJoiner.join(committed, current) }
        var words: [TimedWord] { committedWords + currentWords }

        mutating func commitCurrent() {
            committed = text
            committedWords = words
            current = ""
            currentWords = []
        }
    }

    private(set) var state: State = .idle
    private(set) var segments: [TranscriptSegment] = []
    private(set) var liveText = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: 40)
    private(set) var isOnDevice = false
    private(set) var marks: [MeetingMark] = []

    private let minChunkLength: TimeInterval = 10
    private let maxChunkLength: TimeInterval = 50
    private let pauseLength: TimeInterval = 1.2

    private let engine = AVAudioEngine()
    private let pipe = RecognitionPipe()
    private var recognizer: SFSpeechRecognizer?
    /// The iOS 26 transcriber, stored untyped because the type only exists on iOS 26.
    private var modern: AnyObject?
    private var tasks: [Int: SFSpeechRecognitionTask] = [:]
    private var chunks: [Int: Chunk] = [:]
    private var currentChunk = 0
    private var lastSpeechAt: TimeInterval = 0
    private var accumulated: TimeInterval = 0
    private var resumedAt: Date?
    private var ticker: Timer?
    private var interruptionObserver: NSObjectProtocol?
    private var audioFileName: String?

    private var currentTime: TimeInterval {
        accumulated + (resumedAt.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private var usesModernEngine: Bool { modern != nil }

    // MARK: - Permissions

    nonisolated static func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Controls

    func start(
        requireOnDevice: Bool,
        captureAudioForSpeakers: Bool,
        reduceEchoAndNoise: Bool = false,
        locale: Locale = .current
    ) async throws {
        guard state == .idle else { return }

        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let transcriber = await ModernTranscriber.make(locale: locale) {
            modern = transcriber
            isOnDevice = true
        }
        #endif

        if !usesModernEngine {
            guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
                  recognizer.isAvailable
            else { throw RecorderError.recognizerUnavailable }
            if requireOnDevice && !recognizer.supportsOnDeviceRecognition {
                throw RecorderError.onDeviceUnsupported
            }
            self.recognizer = recognizer
            isOnDevice = recognizer.supportsOnDeviceRecognition
        }

        let session = AVAudioSession.sharedInstance()
        if reduceEchoAndNoise {
            // Apple's voice processing (as used for speakerphone calls) needs play-and-record.
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        } else {
            try session.setCategory(.record, mode: .default)
        }
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        Self.chooseMicrophone(session)

        let input = engine.inputNode
        if reduceEchoAndNoise {
            // Echo cancellation, noise suppression and its own level control. Works best within
            // a metre or two; it can quieten people further away.
            try? input.setVoiceProcessingEnabled(true)
        }
        pipe.boostsQuietSpeech = !reduceEchoAndNoise
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecorderError.noMicrophone }

        segments = []
        chunks = [:]
        liveText = ""
        accumulated = 0
        elapsed = 0
        marks = []

        if captureAudioForSpeakers {
            let name = RecordingStore.newFileName()
            // Speaker separation is optional: carry on without it if the file can't be created.
            if (try? pipe.startAudioFile(at: RecordingStore.url(for: name), inputFormat: format)) != nil {
                audioFileName = name
            }
        }

        pipe.onLevel = { [weak self] level in
            Task { @MainActor in self?.push(level: level) }
        }
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let transcriber = modern as? ModernTranscriber {
            pipe.onBuffer = { buffer in transcriber.append(buffer) }
            try await transcriber.start { [weak self] update in
                Task { @MainActor in self?.apply(update.finalized, volatileText: update.volatileText) }
            }
        }
        #endif

        pipe.installTap(on: input, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            pipe.finishAudioFile()
            RecordingStore.delete(audioFileName)
            audioFileName = nil
            throw error
        }

        resumedAt = Date()
        state = .recording
        if !usesModernEngine { beginChunk() }
        startTicker()
        observeInterruptions()
    }

    func pause() {
        guard state == .recording else { return }
        if !usesModernEngine {
            chunks[currentChunk]?.end = currentTime
            pipe.swap(to: nil)?.endAudio()
        }
        accumulated = currentTime
        resumedAt = nil
        engine.pause()
        state = .paused
        elapsed = accumulated
    }

    func resume() throws {
        guard state == .paused else { return }
        try AVAudioSession.sharedInstance().setActive(true)
        try engine.start()
        resumedAt = Date()
        state = .recording
        if !usesModernEngine { beginChunk() }
    }

    /// Stops capture and waits briefly for the recogniser to deliver its final text.
    func stop() async -> RecordingResult {
        guard state == .recording || state == .paused else {
            return RecordingResult(duration: accumulated, segments: segments, audioFileName: nil)
        }
        if state == .recording {
            chunks[currentChunk]?.end = currentTime
            accumulated = currentTime
            resumedAt = nil
        }
        state = .stopping
        pipe.swap(to: nil)?.endAudio()
        teardownAudio()
        pipe.finishAudioFile()

        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let transcriber = modern as? ModernTranscriber {
            await transcriber.finish()
        }
        #endif
        if !usesModernEngine {
            let deadline = Date().addingTimeInterval(3)
            while !chunks.isEmpty && Date() < deadline {
                try? await Task.sleep(for: .milliseconds(100))
            }
            // Keep whatever partial text arrived for chunks that never finalised.
            for id in chunks.keys.sorted() {
                commit(chunk: id)
            }
            tasks.values.forEach { $0.cancel() }
            tasks = [:]
        }
        // Text the new engine was still working on when recording stopped.
        if !liveText.isEmpty {
            segments.append(TranscriptSegment(start: segments.last?.end ?? 0, end: accumulated, text: liveText))
            liveText = ""
        }
        pipe.onBuffer = nil
        modern = nil

        state = .idle
        elapsed = accumulated
        let fileName = audioFileName
        audioFileName = nil
        return RecordingResult(duration: accumulated, segments: segments, audioFileName: fileName, marks: marks)
    }

    /// Notes the current moment as an action or decision, e.g. just after one was agreed.
    func mark(_ kind: MeetingMark.Kind) {
        guard state == .recording else { return }
        marks.append(MeetingMark(kind: kind, time: currentTime))
    }

    func discard() {
        pipe.swap(to: nil)?.endAudio()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        chunks = [:]
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), let transcriber = modern as? ModernTranscriber {
            transcriber.cancel()
        }
        #endif
        pipe.onBuffer = nil
        modern = nil
        if state != .idle { teardownAudio() }
        pipe.finishAudioFile()
        RecordingStore.delete(audioFileName)
        audioFileName = nil
        state = .idle
    }

    // MARK: - New engine (iOS 26)

    private func apply(_ finalized: TranscriptSegment?, volatileText: String) {
        if let finalized {
            segments.append(finalized)
            segments.sort { $0.start < $1.start }
        }
        liveText = volatileText
    }

    // MARK: - Older engine: recognition chunks

    private func beginChunk() {
        guard let recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        request.addsPunctuation = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        currentChunk += 1
        let id = currentChunk
        chunks[id] = Chunk(start: currentTime)
        lastSpeechAt = currentTime

        tasks[id] = pipe.startTask(recognizer: recognizer, request: request) { [weak self] update in
            Task { @MainActor in self?.handle(chunk: id, update: update) }
        }
        pipe.swap(to: request)?.endAudio()
    }

    private func rotateChunk() {
        chunks[currentChunk]?.end = currentTime
        beginChunk()
    }

    private func handle(chunk id: Int, update: RecognitionUpdate) {
        guard var chunk = chunks[id] else { return }
        let previous = chunk.text

        if let text = update.text, !text.isEmpty {
            // The recogniser sometimes starts its text afresh after a pause. Keep what it had.
            if TranscriptJoiner.isRestart(previous: chunk.current, next: text) {
                chunk.commitCurrent()
            }
            chunk.current = text
            // Word times are relative to the start of this chunk's audio.
            let offset = chunk.start
            chunk.currentWords = update.words.map {
                TimedWord(text: $0.text, start: offset + $0.start, end: offset + $0.end)
            }
        }
        if update.utteranceEnded {
            chunk.commitCurrent()
        }
        chunks[id] = chunk

        if id == currentChunk {
            if chunk.text != previous { lastSpeechAt = currentTime }
            liveText = chunk.text
        }
        if update.isFinished { commit(chunk: id) }
    }

    private func commit(chunk id: Int) {
        tasks[id] = nil
        guard let chunk = chunks.removeValue(forKey: id) else { return }
        let isCurrent = id == currentChunk
        if isCurrent { liveText = "" }

        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let words = chunk.words
            segments.append(TranscriptSegment(
                start: chunk.start,
                end: chunk.end ?? currentTime,
                text: text,
                words: words.isEmpty ? nil : words
            ))
            segments.sort { $0.start < $1.start }
        }

        // The recogniser finished on its own (or failed) while still recording: keep listening.
        if isCurrent && state == .recording {
            let livedFor = currentTime - chunk.start
            if livedFor < 1 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, self.state == .recording, self.chunks[self.currentChunk] == nil else { return }
                    self.beginChunk()
                }
            } else {
                beginChunk()
            }
        }
    }

    // MARK: - Timing and levels

    private func startTicker() {
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func tick() {
        guard state == .recording else { return }
        elapsed = currentTime
        guard !usesModernEngine, let chunk = chunks[currentChunk] else { return }
        let length = currentTime - chunk.start
        let quietFor = currentTime - lastSpeechAt
        let atNaturalPause = !chunk.text.isEmpty && length > minChunkLength && quietFor > pauseLength
        if atNaturalPause || length > maxChunkLength {
            rotateChunk()
        }
    }

    private func push(level: Float) {
        guard state == .recording else { return }
        levels.removeFirst()
        levels.append(level)
    }

    // MARK: - Audio session

    /// Picks the best microphone for a meeting round a table.
    ///
    /// A plugged-in microphone (USB conference microphone or headset) wins. Otherwise the iPhone's
    /// bottom microphone is used in its all-direction pattern: with the phone flat and screen-up,
    /// the back microphone faces the table and sounds muffled.
    private static func chooseMicrophone(_ session: AVAudioSession) {
        let inputs = session.availableInputs ?? []
        let external: [AVAudioSession.Port] = [.usbAudio, .headsetMic, .lineIn]
        if let plugged = inputs.first(where: { external.contains($0.portType) }) {
            try? session.setPreferredInput(plugged)
            return
        }
        guard let builtIn = inputs.first(where: { $0.portType == .builtInMic }) else { return }
        try? session.setPreferredInput(builtIn)
        let sources = builtIn.dataSources ?? []
        guard let source = sources.first(where: { $0.orientation == .bottom })
            ?? sources.first(where: { $0.orientation == .front })
        else { return }
        if source.supportedPolarPatterns?.contains(.omnidirectional) == true {
            try? source.setPreferredPolarPattern(.omnidirectional)
        }
        try? builtIn.setPreferredDataSource(source)
    }

    private func teardownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if engine.inputNode.isVoiceProcessingEnabled {
            try? engine.inputNode.setVoiceProcessingEnabled(false)
        }
        ticker?.invalidate()
        ticker = nil
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
        interruptionObserver = nil
        levels = Array(repeating: 0, count: levels.count)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Pauses when a phone call or another app takes the microphone.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            let type = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard type == AVAudioSession.InterruptionType.began.rawValue else { return }
            Task { @MainActor in self?.pause() }
        }
    }
}

/// What the older recogniser reported for one result.
struct RecognitionUpdate: Sendable {
    var text: String?
    var words: [TimedWord]
    /// The recogniser marked the end of an utterance (it may start fresh text afterwards).
    var utteranceEnded: Bool
    var isFinished: Bool
}

/// Joins recogniser text and spots when it has started afresh rather than revising.
enum TranscriptJoiner {
    static func join(_ first: String, _ second: String) -> String {
        let a = first.trimmingCharacters(in: .whitespaces)
        let b = second.trimmingCharacters(in: .whitespaces)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    /// True when `next` is new speech rather than a revision of `previous`. Revisions keep
    /// the opening word near the start; a restart begins with different words. When unsure
    /// this prefers keeping text (at worst a word repeats) over losing it.
    static func isRestart(previous: String, next: String) -> Bool {
        let before = words(previous)
        let after = words(next)
        guard let firstBefore = before.first, !after.isEmpty else { return false }
        return !after.prefix(3).contains(firstBefore)
    }

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "'" })
            .map(String.init)
    }
}

/// Moves audio from the real-time audio thread to the transcriber and the speaker file.
/// Kept outside the main actor because the tap and recogniser callbacks run on background threads.
private final class RecognitionPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private let gain = AutomaticGain()
    /// Set before the tap is installed. Off when Apple's voice processing already levels the audio.
    var boostsQuietSpeech = true
    private let speakerFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!
    /// Set before the tap is installed and not changed while audio is flowing.
    var onLevel: (@Sendable (Float) -> Void)?
    /// Receives every buffer sent for transcription, e.g. to the iOS 26 transcriber.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// Replaces the request that receives audio and returns the previous one.
    @discardableResult
    func swap(to newRequest: SFSpeechAudioBufferRecognitionRequest?) -> SFSpeechAudioBufferRecognitionRequest? {
        lock.lock()
        defer { lock.unlock() }
        let old = request
        request = newRequest
        return old
    }

    /// Starts writing a 16 kHz mono 16-bit copy of the audio, the format speaker separation expects.
    func startAudioFile(at url: URL, inputFormat: AVAudioFormat) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        RecordingStore.protect(url)
        let converter = AVAudioConverter(from: inputFormat, to: speakerFormat)
        lock.lock()
        audioFile = file
        self.converter = converter
        lock.unlock()
    }

    /// Closes the audio file. AVAudioFile finalises the file when it is released.
    func finishAudioFile() {
        lock.lock()
        audioFile = nil
        converter = nil
        lock.unlock()
    }

    func installTap(on node: AVAudioInputNode, format: AVAudioFormat) {
        node.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            self?.receive(buffer)
        }
    }

    func startTask(
        recognizer: SFSpeechRecognizer,
        request: SFSpeechAudioBufferRecognitionRequest,
        handler: @escaping @Sendable (RecognitionUpdate) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let words = result?.bestTranscription.segments.map {
                TimedWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
            } ?? []
            handler(RecognitionUpdate(
                text: result?.bestTranscription.formattedString,
                words: words,
                utteranceEnded: result?.speechRecognitionMetadata != nil,
                isFinished: (result?.isFinal ?? false) || error != nil
            ))
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        // The engine reuses this buffer's memory for the next callback, and the converters (and
        // the transcriber's queue) can keep the end of one buffer until the next arrives. Working on
        // copies that nothing changes afterwards stops one buffer's join corrupting the next,
        // which was heard as a regular click and fed damaged audio to the transcriber.
        guard let recorded = buffer.copied(), let heard = buffer.copied() else { return }
        lock.lock()
        let current = request
        let file = audioFile
        let converter = converter
        lock.unlock()
        // The kept recording (playback and speaker separation) gets the untouched microphone audio.
        if let file, let converter {
            write(recorded, using: converter, to: file)
        }
        onLevel?(Self.normalisedLevel(of: recorded))
        // Only the transcriber hears the boosted version.
        if boostsQuietSpeech {
            gain.apply(to: heard)
        }
        current?.append(heard)
        onBuffer?(heard)
    }

    private func write(_ buffer: AVAudioPCMBuffer, using converter: AVAudioConverter, to file: AVAudioFile) {
        let ratio = speakerFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: speakerFormat, frameCapacity: capacity) else { return }
        // The converter asks for input until told there is none; hand it this buffer once.
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
            try? file.write(from: output)
        }
    }

    private static func normalisedLevel(of buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0] else { return 0 }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<count {
            sum += samples[i] * samples[i]
        }
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, 0.000_01))
        return max(0, min(1, (decibels + 50) / 50))
    }
}

/// Lifts quiet speech (people further from the iPhone) towards a steady level for the
/// transcriber. It only adjusts while someone is speaking, so pauses and background hiss
/// aren't raised, and a limiter near full scale stops loud voices distorting.
/// Runs on the audio thread only.
final class AutomaticGain: @unchecked Sendable {
    /// About −20 dBFS: a comfortable speech level for recognition.
    static let targetLevel: Float = 0.1
    /// At most about +12 dB, so room echo and noise aren't raised too far.
    static let maximumGain: Float = 4
    /// Levels this many times above the background count as speech.
    static let speechRatio: Float = 3
    private(set) var gain: Float = 1
    private(set) var noiseFloor: Float = 0.003

    /// The gain to aim for given a buffer's RMS level.
    static func desiredGain(forLevel rms: Float) -> Float {
        min(maximumGain, max(1, targetLevel / max(rms, 0.002)))
    }

    /// Passes quiet samples through unchanged and softly limits anything near full scale.
    static func limit(_ sample: Float) -> Float {
        let knee: Float = 0.8
        let magnitude = abs(sample)
        guard magnitude > knee else { return sample }
        let limited = knee + (1 - knee) * tanhf((magnitude - knee) / (1 - knee))
        return sample < 0 ? -limited : limited
    }

    func apply(to buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        var sum: Float = 0
        for i in 0..<count {
            sum += channels[0][i] * channels[0][i]
        }
        let rms = (sum / Float(count)).squareRoot()

        // Background level: follows quiet moments quickly and loud ones very slowly.
        noiseFloor = rms < noiseFloor ? rms : noiseFloor + (rms - noiseFloor) * 0.002
        let startGain = gain
        if rms > max(noiseFloor, 0.001) * Self.speechRatio {
            let desired = Self.desiredGain(forLevel: rms)
            // Turn down quickly when speech gets loud, up gently for quieter voices.
            gain += (desired - gain) * (desired < gain ? 0.5 : 0.1)
        }

        guard startGain > 1.01 || gain > 1.01 else { return }
        // Glide from the old gain to the new one across the buffer. A jump at the join between
        // buffers would be a click.
        let step = (gain - startGain) / Float(count)
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = channels[channel]
            for i in 0..<count {
                samples[i] = Self.limit(samples[i] * (startGain + step * Float(i)))
            }
        }
    }
}

extension AVAudioPCMBuffer {
    /// A copy with its own memory, safe to keep or change after the audio callback returns.
    func copied() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(frameLength, 1)) else { return nil }
        copy.frameLength = frameLength
        let source = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            guard let fromData = from.mData, let toData = to.mData else { continue }
            memcpy(toData, fromData, Int(min(from.mDataByteSize, to.mDataByteSize)))
        }
        return copy
    }
}
