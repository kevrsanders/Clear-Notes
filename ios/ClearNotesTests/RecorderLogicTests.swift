import AVFoundation
import XCTest
@testable import ClearNotes

final class RecorderLogicTests: XCTestCase {
    // MARK: - Restart detection (older recogniser)

    func testRevisionIsNotARestart() {
        XCTAssertFalse(TranscriptJoiner.isRestart(previous: "I think we are", next: "I think we're ready to go"))
        XCTAssertFalse(TranscriptJoiner.isRestart(previous: "so the plan", next: "So, the plan is"))
    }

    func testNewUtteranceIsARestart() {
        XCTAssertTrue(TranscriptJoiner.isRestart(previous: "I think we are ready", next: "One as well"))
        XCTAssertTrue(TranscriptJoiner.isRestart(previous: "Okay", next: "Next item is the budget"))
    }

    func testEmptyTextIsNeverARestart() {
        XCTAssertFalse(TranscriptJoiner.isRestart(previous: "", next: "Hello"))
        XCTAssertFalse(TranscriptJoiner.isRestart(previous: "Hello", next: ""))
    }

    func testJoinSkipsEmptyParts() {
        XCTAssertEqual(TranscriptJoiner.join("I think we are ready.", "One as well."), "I think we are ready. One as well.")
        XCTAssertEqual(TranscriptJoiner.join("", "Hello"), "Hello")
        XCTAssertEqual(TranscriptJoiner.join("Hello ", " "), "Hello")
    }

    // MARK: - Automatic gain

    func testQuietSpeechIsBoostedWithinLimits() {
        XCTAssertEqual(AutomaticGain.desiredGain(forLevel: 0.05), 2, accuracy: 0.001)
        XCTAssertEqual(AutomaticGain.desiredGain(forLevel: 0.001), AutomaticGain.maximumGain)
    }

    func testNormalAndLoudSpeechIsLeftAlone() {
        XCTAssertEqual(AutomaticGain.desiredGain(forLevel: 0.1), 1)
        XCTAssertEqual(AutomaticGain.desiredGain(forLevel: 0.6), 1)
    }

    func testLimiterOnlyTouchesPeaks() {
        XCTAssertEqual(AutomaticGain.limit(0.5), 0.5)
        XCTAssertEqual(AutomaticGain.limit(-0.7), -0.7)
        let limited = AutomaticGain.limit(1.6)
        XCTAssertGreaterThan(limited, 0.8)
        XCTAssertLessThan(limited, 1)
        XCTAssertEqual(AutomaticGain.limit(-1.6), -limited)
    }

    /// A 16 kHz mono buffer holding a square wave whose RMS level is `level`.
    private func buffer(level: Float) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1600))
        buffer.frameLength = 1600
        let samples = try XCTUnwrap(buffer.floatChannelData?[0])
        for i in 0..<1600 {
            samples[i] = i % 2 == 0 ? level : -level
        }
        return buffer
    }

    func testPausesDoNotRaiseTheGain() throws {
        let gain = AutomaticGain()
        for _ in 0..<50 {
            gain.apply(to: try buffer(level: 0.002))
        }
        XCTAssertEqual(gain.gain, 1, accuracy: 0.001)
    }

    func testQuietSpeechRaisesTheGain() throws {
        let gain = AutomaticGain()
        for _ in 0..<10 {
            gain.apply(to: try buffer(level: 0.002))
        }
        for _ in 0..<50 {
            gain.apply(to: try buffer(level: 0.03))
        }
        XCTAssertGreaterThan(gain.gain, 2.5)
        XCTAssertLessThanOrEqual(gain.gain, AutomaticGain.maximumGain)
    }
}

final class AudioRetentionTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_000_000)

    func testExpiryDates() throws {
        let week = try XCTUnwrap(AudioRetention.oneWeek.expiry(from: date))
        XCTAssertEqual(week.timeIntervalSince(date), 7 * 24 * 3600, accuracy: 3600)
        XCTAssertNil(AudioRetention.untilDeleted.expiry(from: date))
        XCTAssertNil(AudioRetention.whenNotesReady.expiry(from: date))
    }

    func testWhichOptionsKeepAudio() {
        XCTAssertFalse(AudioRetention.whenNotesReady.keepsAudio)
        XCTAssertTrue(AudioRetention.oneDay.keepsAudio)
        XCTAssertTrue(AudioRetention.untilDeleted.keepsAudio)
        XCTAssertEqual(AudioRetention.default, .oneWeek)
    }
}
