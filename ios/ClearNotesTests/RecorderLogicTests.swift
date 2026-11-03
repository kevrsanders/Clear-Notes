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

    /// The gain glides across a buffer instead of jumping at its start, which would click.
    func testGainChangesSmoothlyAcrossABuffer() throws {
        let gain = AutomaticGain()
        let speech = try buffer(level: 0.03)
        gain.apply(to: speech)
        let samples = try XCTUnwrap(speech.floatChannelData?[0])
        XCTAssertGreaterThan(gain.gain, 1.1)
        XCTAssertEqual(samples[0], 0.03, accuracy: 0.0001, "Starts at the previous gain")
        XCTAssertEqual(samples[1599], -0.03 * gain.gain, accuracy: 0.001, "Ends at the new gain")
    }

    /// Copies have their own memory, so the engine reusing its buffer can't change them.
    func testCopiedBuffersAreIndependent() throws {
        let original = try buffer(level: 0.2)
        let copy = try XCTUnwrap(original.copied())
        XCTAssertEqual(copy.frameLength, original.frameLength)
        original.floatChannelData?[0][0] = 0.9
        XCTAssertEqual(copy.floatChannelData?[0][0], 0.2)
        XCTAssertEqual(copy.floatChannelData?[0][1599], -0.2)
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

final class LockScreenControlsTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    func testPausingStopsTheTimerAndResumingCountsOnlyRecordedTime() {
        let recording = RecordingActivityAttributes.ContentState(timerStart: start)

        let paused = RecordingLiveActivity.paused(recording, at: start.addingTimeInterval(90))
        XCTAssertTrue(paused.isPaused)
        XCTAssertEqual(paused.pausedAt, start.addingTimeInterval(90))

        // Resumed five minutes later with 90 seconds recorded: the timer carries on from 1:30.
        let resumeTime = start.addingTimeInterval(390)
        let resumed = RecordingLiveActivity.resumed(paused, elapsed: 90, at: resumeTime)
        XCTAssertFalse(resumed.isPaused)
        XCTAssertEqual(resumeTime.timeIntervalSince(resumed.timerStart), 90)
    }

    func testMarksAreCountedAndConfirmed() {
        var state = RecordingActivityAttributes.ContentState(timerStart: start)
        XCTAssertNil(state.marksText)

        state = RecordingLiveActivity.marked(state, kind: .action, at: 125)
        XCTAssertEqual(state.note, "Action marked at 2:05")
        state = RecordingLiveActivity.marked(state, kind: .action, at: 300)
        state = RecordingLiveActivity.marked(state, kind: .decision, at: 310)

        XCTAssertEqual(state.marksText, "2 actions · 1 decision marked")
        XCTAssertNil(RecordingLiveActivity.paused(state).note, "The confirmation clears on pause")
    }
}
