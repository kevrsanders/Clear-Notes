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
}
