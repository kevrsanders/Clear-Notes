import SwiftData
import XCTest
@testable import ClearNotes

@MainActor
final class SpeakerEditingTests: XCTestCase {
    private func makeMeeting() throws -> (ModelContainer, Meeting) {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let meeting = Meeting(title: "Test", segments: [
            TranscriptSegment(start: 0, end: 2, text: "Can you tell Sam?", speakerID: "S1"),
            TranscriptSegment(start: 2, end: 4, text: "I haven't got football.", speakerID: "S1"),
        ])
        container.mainContext.insert(meeting)
        meeting.speakers = [Speaker(id: "S1", number: 1), Speaker(id: "S2", number: 2)]
        return (container, meeting)
    }

    func testNewSpeakerTakesTheNextNumberAndTheLine() throws {
        let (_, meeting) = try makeMeeting()
        let before = meeting.revision

        let speaker = meeting.addSpeaker()
        meeting.reassignSegment(meeting.segments[1].id, to: speaker.id)

        XCTAssertEqual(speaker.number, 3)
        XCTAssertEqual(meeting.speakers.map(\.id), ["S1", "S2", "S3"])
        XCTAssertEqual(meeting.segments.map(\.speakerID), ["S1", "S3"])
        XCTAssertGreaterThan(meeting.revision, before)
    }

    func testMergingMovesLinesAndRemovesTheSpeaker() throws {
        let (_, meeting) = try makeMeeting()
        meeting.reassignSegment(meeting.segments[1].id, to: "S2")
        meeting.mergeSpeaker("S2", into: "S1")

        XCTAssertEqual(meeting.speakers.map(\.id), ["S1"])
        XCTAssertEqual(meeting.segments.map(\.speakerID), ["S1", "S1"])
    }
}
