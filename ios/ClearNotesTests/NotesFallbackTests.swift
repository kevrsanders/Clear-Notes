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

    func testSafetyBlocksAreRecognisedAndWorded() throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Apple Intelligence reasons need iOS 26") }
        let blocked = NSError(domain: "FoundationModels", code: 1, userInfo: [NSLocalizedDescriptionKey: "Detected content likely to be unsafe."])
        XCTAssertEqual(NotesEnhancers.reason(for: blocked), "Apple's safety filter declined part of the conversation")
    }

    func testSuccessfulNotesHaveNoCaveat() async throws {
        let meeting = try makeMeeting()
        meeting.notesCaveat = "Left over from an earlier attempt"

        await MeetingProcessor.process(meeting, enhancer: HeuristicEnhancer(), separator: nil)

        XCTAssertEqual(meeting.processingState, .ready)
        XCTAssertNil(meeting.notesCaveat)
    }
}

final class NotesTextTests: XCTestCase {
    func testHTMLListsBecomeBullets() {
        let html = "<ul><li>The team&#39;s rota changes next week.</li><li>The migration is the biggest challenge.</li></ul>"
        XCTAssertEqual(
            NotesText.bulletList(html),
            "- The team's rota changes next week.\n- The migration is the biggest challenge."
        )
    }

    func testOtherBulletStylesAreNormalised() {
        XCTAssertEqual(NotesText.bullets(from: "• One\n* Two\n1. Three\n- Four"), ["One", "Two", "Three", "Four"])
        XCTAssertEqual(NotesText.plain("<b>Patch</b> &amp; reboot"), "Patch & reboot")
    }
}

final class ActionListTests: XCTestCase {
    func testRepeatedActionsAreMerged() {
        let actions = [
            ExtractedAction(task: "Send the revised firewall change to CAB", owner: "Priya"),
            ExtractedAction(task: "Send revised firewall change to the CAB", owner: nil),
            ExtractedAction(task: "Book the server room for patching", owner: "Tom"),
        ]
        XCTAssertEqual(ActionList.deduplicated(actions).map(\.task), [
            "Send the revised firewall change to CAB",
            "Book the server room for patching",
        ])
    }

    func testSimilarActionsForDifferentPeopleAreKept() {
        let actions = [
            ExtractedAction(task: "Send the patching report", owner: "Priya"),
            ExtractedAction(task: "Send the patching report", owner: "Tom"),
        ]
        XCTAssertEqual(ActionList.deduplicated(actions).count, 2)
    }
}
