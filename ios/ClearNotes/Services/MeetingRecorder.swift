import AVFoundation
import Observation
import Speech

struct RecordingResult {
    var duration: TimeInterval
    var segments: [TranscriptSegment]
    /// Temporary audio for speaker separation, if it was captured.
    var audioFileName: String?
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
/// Speech is recognised in short chunks. A chunk ends at a natural pause (or after
/// `maxChunkLength`) and becomes a timestamped transcript segment. Restarting the
/// recogniser like this keeps long meetings going and gives the transcript timestamps.
///
/// When speaker identification is on, a 16 kHz mono copy of the audio is written to a
/// temporary file for speaker separation. It is deleted once speakers are identified.
@MainActor
@Observable
final class MeetingRecorder {
    enum State: Equatable {
        case idle, recording, paused, stopping
    }

    private struct Chunk {
        var start: TimeInterval
        var end: TimeInterval?
        var text = ""
        var words: [TimedWord] = []
    }

    private(set) var state: State = .idle
    private(set) var segments: [TranscriptSegment] = []
    private(set) var liveText = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: 40)
    private(set) var isOnDevice = false

    private let minChunkLength: TimeInterval = 10
    private let maxChunkLength: TimeInterval = 50
    private let pauseLength: TimeInterval = 1.2

    private let engine = AVAudioEngine()
    private let pipe = RecognitionPipe()
    private var recognizer: SFSpeechRecognizer?
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

    // MARK: - Permissions

    nonisolated static func requestPermissions() async -> Bool {
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speechStatus == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Controls

    func start(requireOnDevice: Bool, captureAudioForSpeakers: Bool, locale: Locale = .current) throws {
        guard state == .idle else { return }

        guard let recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(),
              recognizer.isAvailable
        else { throw RecorderError.recognizerUnavailable }
        if requireOnDevice && !recognizer.supportsOnDeviceRecognition {
            throw RecorderError.onDeviceUnsupported
        }
        self.recognizer = recognizer
        isOnDevice = recognizer.supportsOnDeviceRecognition

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .default)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw RecorderError.noMicrophone }

        segments = []
        chunks = [:]
        liveText = ""
        accumulated = 0
        elapsed = 0

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
        beginChunk()
        startTicker()
        observeInterruptions()
    }

    func pause() {
        guard state == .recording else { return }
        chunks[currentChunk]?.end = currentTime
        accumulated = currentTime
        resumedAt = nil
        pipe.swap(to: nil)?.endAudio()
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
        beginChunk()
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

        state = .idle
        elapsed = accumulated
        let fileName = audioFileName
        audioFileName = nil
        return RecordingResult(duration: accumulated, segments: segments, audioFileName: fileName)
    }

    func discard() {
        pipe.swap(to: nil)?.endAudio()
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
        chunks = [:]
        if state != .idle { teardownAudio() }
        pipe.finishAudioFile()
        RecordingStore.delete(audioFileName)
        audioFileName = nil
        state = .idle
    }

    // MARK: - Recognition chunks

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

        tasks[id] = pipe.startTask(recognizer: recognizer, request: request) { [weak self] text, words, isFinished in
            Task { @MainActor in self?.handle(chunk: id, text: text, words: words, isFinished: isFinished) }
        }
        pipe.swap(to: request)?.endAudio()
    }

    private func rotateChunk() {
        chunks[currentChunk]?.end = currentTime
        beginChunk()
    }

    private func handle(chunk id: Int, text: String?, words: [TimedWord], isFinished: Bool) {
        if let start = chunks[id]?.start, !words.isEmpty {
            // Word times are relative to the start of this chunk's audio.
            chunks[id]?.words = words.map { TimedWord(text: $0.text, start: start + $0.start, end: start + $0.end) }
        }
        if let text, !text.isEmpty, chunks[id]?.text != text {
            chunks[id]?.text = text
            if id == currentChunk {
                lastSpeechAt = currentTime
                liveText = text
            }
        }
        if isFinished { commit(chunk: id) }
    }

    private func commit(chunk id: Int) {
        tasks[id] = nil
        guard let chunk = chunks.removeValue(forKey: id) else { return }
        let isCurrent = id == currentChunk
        if isCurrent { liveText = "" }

        let text = chunk.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            segments.append(TranscriptSegment(
                start: chunk.start,
                end: chunk.end ?? currentTime,
                text: text,
                words: chunk.words.isEmpty ? nil : chunk.words
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
        guard let chunk = chunks[currentChunk] else { return }
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

    private func teardownAudio() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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

/// Moves audio from the real-time audio thread to the current recognition request.
/// Kept outside the main actor because the tap and recogniser callbacks run on background threads.
private final class RecognitionPipe: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private let speakerFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false
    )!
    /// Set before the tap is installed and not changed while audio is flowing.
    var onLevel: (@Sendable (Float) -> Void)?

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
        handler: @escaping @Sendable (_ text: String?, _ words: [TimedWord], _ isFinished: Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let isFinished = (result?.isFinal ?? false) || error != nil
            let words = result?.bestTranscription.segments.map {
                TimedWord(text: $0.substring, start: $0.timestamp, end: $0.timestamp + $0.duration)
            } ?? []
            handler(result?.bestTranscription.formattedString, words, isFinished)
        }
    }

    private func receive(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        let current = request
        let file = audioFile
        let converter = converter
        lock.unlock()
        current?.append(buffer)
        if let file, let converter {
            write(buffer, using: converter, to: file)
        }
        onLevel?(Self.normalisedLevel(of: buffer))
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
