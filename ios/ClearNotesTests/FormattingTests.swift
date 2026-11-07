import XCTest
@testable import ClearNotes

final class FormattingTests: XCTestCase {
    func testClockString() {
        XCTAssertEqual(TimeInterval(0).clockString, "0:00")
        XCTAssertEqual(TimeInterval(245.9).clockString, "4:05")
        XCTAssertEqual(TimeInterval(3729).clockString, "1:02:09")
    }

    func testDurationString() {
        XCTAssertEqual(TimeInterval(20).durationString, "Under a minute")
        XCTAssertEqual(TimeInterval(60).durationString, "1 min")
        XCTAssertEqual(TimeInterval(3600).durationString, "1 hr")
        XCTAssertEqual(TimeInterval(3900).durationString, "1 hr 5 min")
    }

    func testSegmentMatchingFindsSourceOfQuote() {
        let segments = [
            TranscriptSegment(start: 0, end: 10, text: "Welcome to the project board."),
            TranscriptSegment(start: 10, end: 20, text: "Sam will circulate the revised timeline tomorrow."),
        ]
        XCTAssertEqual(segments.segment(matching: "circulate the revised timeline")?.start, 10)
        XCTAssertEqual(segments.segment(matching: "Sam to circulate revised timeline")?.start, 10)
        XCTAssertNil(segments.segment(matching: "completely unrelated words here"))
        XCTAssertNil(segments.segment(matching: nil))
    }
}

final class AppAccentTests: XCTestCase {
    func testEveryColourHasEightDistinctSpeakerColours() {
        for accent in AppAccent.allCases {
            XCTAssertEqual(accent.speakerColors.count, 8, accent.title)
            XCTAssertEqual(Set(accent.speakerColors).count, 8, "\(accent.title) repeats a speaker colour")
            XCTAssertEqual(accent.gradient.count, 2, accent.title)
        }
    }

    func testTealIsTheDefaultAndOldValuesFallBack() {
        XCTAssertEqual(AppAccent(rawValue: "teal"), .teal)
        XCTAssertNil(AppAccent(rawValue: "violet"), "There's no violet any more; the default (teal) applies")
        XCTAssertEqual(AppAccent.allCases.map(\.title), ["Teal", "Ocean", "Sage", "Amber", "Graphite"])
    }
}
