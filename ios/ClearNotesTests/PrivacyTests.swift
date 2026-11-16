import AVFoundation
import XCTest
@testable import ClearNotes

/// Clear Notes contacts no third party unless the user asks: the speaker models are built in, and
/// model downloads are blocked from launch.
final class PrivacyTests: XCTestCase {
    func testSpeakerModelsAreBuiltIntoTheApp() {
        XCTAssertTrue(BundledSpeakerModels.isAvailable, "Run scripts/fetch_speaker_models.py before building")
        XCTAssertTrue(SpeakerSeparators.isSupported)
    }

    func testModelDownloadsAreBlockedFromLaunch() {
        XCTAssertTrue(ModelDownloads.isBlocked)
    }

    func testSpeakersAreSeparatedWithTheBuiltInModels() async throws {
        ModelDownloads.isBlocked = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("two-voices-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeTwoVoices(to: url, seconds: 16)
        let separator = try XCTUnwrap(SpeakerSeparators.best())
        // Made-up audio may or may not count as speech. What matters is that the built-in models
        // load and run with downloads blocked.
        _ = try await separator.separate(audioAt: url, expectedSpeakers: nil)
    }

    func testPLDAParametersAreRead() throws {
        let values: [Float] = [0.5, 1.25, -2]
        let data = values.withUnsafeBytes { Data($0) }
        let json = #"{"tensors":{"psi":{"data_base64":"\#(data.base64EncodedString())"}}}"#
        XCTAssertEqual(try BundledSpeakerModels.pldaPsi(from: Data(json.utf8)), [0.5, 1.25, -2])
        XCTAssertThrowsError(try BundledSpeakerModels.pldaPsi(from: Data("{}".utf8)))

        let directory = try XCTUnwrap(BundledSpeakerModels.directory)
        let builtIn = try Data(contentsOf: directory.appendingPathComponent(BundledSpeakerModels.pldaParameters))
        XCTAssertFalse(try BundledSpeakerModels.pldaPsi(from: builtIn).isEmpty)
    }

    /// 16 kHz mono, as recordings are saved: two pitches taking turns every two seconds, with a
    /// syllable-like rhythm.
    private func writeTwoVoices(to url: URL, seconds: Int) throws {
        let rate = Double(AudioSamples.sampleRate)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: rate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let count = Int(rate) * seconds
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(count)))
        buffer.frameLength = AVAudioFrameCount(count)
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<count {
            let time = Double(index) / rate
            let pitch = Int(time / 2) % 2 == 0 ? 140.0 : 230.0
            let rhythm = 0.5 + 0.5 * sin(2 * .pi * 4 * time)
            var value = 0.0
            for harmonic in 1...5 {
                value += sin(2 * .pi * pitch * Double(harmonic) * time) / Double(harmonic)
            }
            samples[index] = Float(0.1 * rhythm * value)
        }
        try file.write(from: buffer)
    }
}
