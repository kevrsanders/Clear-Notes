import AVFoundation
import Foundation
#if canImport(FluidAudio)
import FluidAudio
#endif

/// A stretch of audio attributed to one voice. `speaker` is the separator's own label.
struct SpeakerTurn: Equatable, Sendable {
    var speaker: String
    var start: TimeInterval
    var end: TimeInterval
}

enum SpeakerSeparationError: LocalizedError {
    case unsupportedAudio

    var errorDescription: String? {
        "The audio couldn't be read for speaker separation."
    }
}

/// Finds who spoke when in a recording.
protocol SpeakerSeparating: Sendable {
    /// `expectedSpeakers` fixes the number of voices when the user knows it.
    func separate(audioAt url: URL, expectedSpeakers: Int?) async throws -> [SpeakerTurn]
}

enum SpeakerSeparators {
    /// Whether this build includes on-device speaker separation.
    static var isSupported: Bool {
        #if canImport(FluidAudio)
        true
        #else
        false
        #endif
    }

    static func best() -> SpeakerSeparating? {
        #if canImport(FluidAudio)
        FluidSpeakerSeparator()
        #else
        nil
        #endif
    }

    /// Downloads the speaker models (once) so the first meeting doesn't have to wait.
    /// Only model files are downloaded; no meeting data leaves the iPhone.
    static func prepareModels() async throws {
        #if canImport(FluidAudio)
        try await OfflineDiarizerManager().prepareModels()
        #endif
    }
}

#if canImport(FluidAudio)
/// On-device speaker separation using FluidAudio's Core ML models (pyannote-based).
struct FluidSpeakerSeparator: SpeakerSeparating {
    func separate(audioAt url: URL, expectedSpeakers: Int?) async throws -> [SpeakerTurn] {
        var samples = try AudioSamples.load(from: url)
        // Too short to tell voices apart.
        guard samples.count >= AudioSamples.sampleRate * 3 else { return [] }
        // Pad short clips with silence so the model always gets at least one full window.
        let minimum = AudioSamples.sampleRate * 12
        if samples.count < minimum {
            samples += [Float](repeating: 0, count: minimum - samples.count)
        }
        var config = OfflineDiarizerConfig.default
        if let expectedSpeakers {
            config.clustering.numSpeakers = expectedSpeakers
        } else {
            // Slightly keener to split voices than the default (0.6). Quiet, distant voices
            // otherwise merge into nearby ones, and merging back is one tap for the user.
            config.clustering.threshold = 0.55
        }
        let manager = OfflineDiarizerManager(config: config)
        try await manager.prepareModels()
        let result = try await manager.process(audio: samples)
        return result.segments.map {
            SpeakerTurn(
                speaker: $0.speakerId,
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds)
            )
        }
    }
}
#endif

enum AudioSamples {
    static let sampleRate = 16_000

    /// Reads the 16 kHz mono file written during recording as floating-point samples.
    static func load(from url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard format.sampleRate == 16_000, format.channelCount == 1 else {
            throw SpeakerSeparationError.unsupportedAudio
        }
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length))
        else { return [] }
        try file.read(into: buffer)
        guard let channel = buffer.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }
}
