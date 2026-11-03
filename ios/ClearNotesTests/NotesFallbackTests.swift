import SwiftData
import XCTest
@testable import ClearNotes

@MainActor
final class NotesFallbackTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    /// Stands in for Apple Intelligence failing, e.g. "Exceeded rate limit" in the foreground.
    private struct FailingEnhancer: NotesEnhancer {
        let sourceName = "Test AI"

        func enhance(segments: [TranscriptSegment], speakers: [Speaker], userNotes: String) async throws -> MeetingInsights {
            throw URLError(.cannotParseResponse)
        }
    }

    private func makeMeeting() throws -> Meeting {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let meeting = Meeting(title: "Test", segments: [
            TranscriptSegment(start: 0, end: 4, text: "We looked at the patching backlog for the servers this week."),
            TranscriptSegment(start: 4, end: 8, text: "I'll send the revised firewall change to the CAB by Friday."),
        ])
        container.mainContext.insert(meeting)
        return meeting
    }

    func testFailedAINotesFallBackToBasicNotesWithAReason() async throws {
        let meeting = try makeMeeting()

        await MeetingProcessor.process(meeting, enhancer: FailingEnhancer(), separator: nil)

        XCTAssertEqual(meeting.processingState, .ready)
        XCTAssertNil(meeting.processingError)
        XCTAssertEqual(meeting.insightsSource, HeuristicEnhancer().sourceName)
        XCTAssertTrue(meeting.notesCaveat?.contains("basic extraction") == true)
        XCTAssertFalse(meeting.summary.isEmpty)
        XCTAssertTrue(meeting.actions.contains { $0.text.contains("firewall change") })
    }

    func testReasonsAreReadable() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Apple Intelligence reasons need iOS 26") }
        let systemError = NSError(domain: "FoundationModels.LanguageModelError", code: -1)
        XCTAssertEqual(NotesEnhancers.reason(for: systemError), "it hit an internal error on this iPhone (LanguageModelError -1)")
        XCTAssertEqual(NotesEnhancers.reason(for: NotesEnhancerError.busy), "it was busy")
    }

    func testSuccessfulNotesHaveNoCaveat() async throws {
        let meeting = try makeMeeting()
        meeting.notesCaveat = "Left over from an earlier attempt"

        await MeetingProcessor.process(meeting, enhancer: HeuristicEnhancer(), separator: nil)

        XCTAssertEqual(meeting.processingState, .ready)
        XCTAssertNil(meeting.notesCaveat)
    }
}
