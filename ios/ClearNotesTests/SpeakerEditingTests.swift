import SwiftData
import XCTest
@testable import ClearNotes

@MainActor
final class SpeakerEditingTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    private func makeMeeting() throws -> Meeting {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let meeting = Meeting(title: "Test", segments: [
            TranscriptSegment(start: 0, end: 2, text: "Can you tell Sam?", speakerID: "S1"),
            TranscriptSegment(start: 2, end: 4, text: "I haven't got football.", speakerID: "S1"),
        ])
        self.container = container
        container.mainContext.insert(meeting)
        meeting.speakers = [Speaker(id: "S1", number: 1), Speaker(id: "S2", number: 2)]
        return meeting
    }

    func testNewSpeakerTakesTheNextNumberAndTheLine() throws {
        let meeting = try makeMeeting()
        let before = meeting.revision

        let speaker = meeting.addSpeaker()
        meeting.reassignSegment(meeting.segments[1].id, to: speaker.id)

        XCTAssertEqual(speaker.number, 3)
        XCTAssertEqual(meeting.speakers.map(\.id), ["S1", "S2", "S3"])
        XCTAssertEqual(meeting.segments.map(\.speakerID), ["S1", "S3"])
        XCTAssertGreaterThan(meeting.revision, before)
    }

    func testMergingMovesLinesAndRemovesTheSpeaker() throws {
        let meeting = try makeMeeting()
        meeting.reassignSegment(meeting.segments[1].id, to: "S2")
        meeting.mergeSpeaker("S2", into: "S1")

        XCTAssertEqual(meeting.speakers.map(\.id), ["S1"])
        XCTAssertEqual(meeting.segments.map(\.speakerID), ["S1", "S1"])
    }
}

final class SpeakerNamesTests: XCTestCase {
    func testNamesFollowTheVoicesThatMatch() {
        let old = [
            TranscriptSegment(start: 0, end: 10, text: "a", speakerID: "S1"),
            TranscriptSegment(start: 10, end: 14, text: "b", speakerID: "S2"),
            TranscriptSegment(start: 14, end: 30, text: "c", speakerID: "S1"),
        ]
        let oldSpeakers = [
            Speaker(id: "S1", number: 1, name: "Priya"),
            Speaker(id: "S2", number: 2, name: "Tom"),
        ]
        // Regrouped into three voices: A is Priya, B is Tom, C is a new voice split off from Priya's lines.
        let new = [
            TranscriptSegment(start: 0, end: 10, text: "a", speakerID: "A"),
            TranscriptSegment(start: 10, end: 14, text: "b", speakerID: "B"),
            TranscriptSegment(start: 14, end: 20, text: "c", speakerID: "A"),
            TranscriptSegment(start: 20, end: 30, text: "d", speakerID: "C"),
        ]
        let newSpeakers = [
            Speaker(id: "A", number: 1),
            Speaker(id: "B", number: 2),
            Speaker(id: "C", number: 3),
        ]

        let renamed = SpeakerNames.carry(from: old, oldSpeakers: oldSpeakers, to: new, newSpeakers: newSpeakers)

        XCTAssertEqual(renamed.map(\.name), ["Priya", "Tom", nil], "Each name is used once, by the best match")
    }

    func testUnnamedSpeakersCarryNothing() {
        let old = [TranscriptSegment(start: 0, end: 10, text: "a", speakerID: "S1")]
        let new = [TranscriptSegment(start: 0, end: 10, text: "a", speakerID: "A")]
        let renamed = SpeakerNames.carry(
            from: old, oldSpeakers: [Speaker(id: "S1", number: 1)],
            to: new, newSpeakers: [Speaker(id: "A", number: 1)]
        )
        XCTAssertNil(renamed.first?.name)
    }
}
