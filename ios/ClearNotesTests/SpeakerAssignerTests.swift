import XCTest
@testable import ClearNotes

final class SpeakerAssignerTests: XCTestCase {
    /// One word per second starting at `from`.
    private func words(_ text: String, from start: TimeInterval = 0) -> [TimedWord] {
        text.split(separator: " ").enumerated().map { index, word in
            TimedWord(text: String(word), start: start + TimeInterval(index), end: start + TimeInterval(index + 1))
        }
    }

    func testSplitsSegmentWhereTheSpeakerChanges() {
        let segment = TranscriptSegment(start: 0, end: 8, text: "", words: words("I think we're ready Sounds good to me"))
        let turns = [
            SpeakerTurn(speaker: "spk_a", start: 0, end: 4),
            SpeakerTurn(speaker: "spk_b", start: 4, end: 8),
        ]
        let result = SpeakerAssigner.assign([segment], turns: turns)

        XCTAssertEqual(result.segments.map(\.text), ["I think we're ready", "Sounds good to me"])
        XCTAssertEqual(result.segments.map(\.speakerID), ["S1", "S2"])
        XCTAssertEqual(result.segments.first?.id, segment.id, "The first part keeps the original ID")
        XCTAssertEqual(result.segments[1].start, 4)
        XCTAssertEqual(result.speakers.map(\.number), [1, 2])
        XCTAssertTrue(result.segments.allSatisfy { $0.words == nil })
    }

    func testShortBlipsStayWithTheSurroundingSpeaker() {
        let segment = TranscriptSegment(start: 0, end: 10, text: "", words: words("one two three four five six seven eight nine ten"))
        let turns = [
            SpeakerTurn(speaker: "a", start: 0, end: 4),
            SpeakerTurn(speaker: "b", start: 4, end: 5),
            SpeakerTurn(speaker: "a", start: 5, end: 10),
        ]
        let result = SpeakerAssigner.assign([segment], turns: turns)

        XCTAssertEqual(result.segments.count, 1)
        XCTAssertEqual(result.segments.first?.speakerID, "S1")
        XCTAssertEqual(result.speakers.map(\.id), ["S1"], "A speaker who owns no lines is left out")
    }

    func testSegmentsWithoutTimingsUseTheDominantSpeaker() {
        let segment = TranscriptSegment(start: 0, end: 10, text: "Hello there")
        let turns = [
            SpeakerTurn(speaker: "a", start: 0, end: 3),
            SpeakerTurn(speaker: "b", start: 3, end: 10),
        ]
        let result = SpeakerAssigner.assign([segment], turns: turns)

        XCTAssertEqual(result.segments.first?.speakerID, "S2")
        XCTAssertEqual(result.speakers, [Speaker(id: "S2", number: 2)])
    }

    func testWordsBetweenTurnsGoToTheNearestSpeaker() {
        XCTAssertEqual(SpeakerAssigner.speaker(at: 5.2, turns: [
            SpeakerTurn(speaker: "a", start: 0, end: 5),
            SpeakerTurn(speaker: "b", start: 8, end: 10),
        ]), "a")
    }

    func testNoTurnsLeavesTranscriptUnchanged() {
        let segment = TranscriptSegment(start: 0, end: 5, text: "Hello")
        let result = SpeakerAssigner.assign([segment], turns: [])
        XCTAssertEqual(result.segments, [segment])
        XCTAssertTrue(result.speakers.isEmpty)
    }

    func testAvatarInitials() {
        XCTAssertEqual(Avatar.initials(of: "Priya Shah"), "PS")
        XCTAssertEqual(Avatar.initials(of: "tom"), "T")
        XCTAssertNil(Avatar.initials(of: "  "))
        XCTAssertNil(Avatar.initials(of: nil))
    }
}
