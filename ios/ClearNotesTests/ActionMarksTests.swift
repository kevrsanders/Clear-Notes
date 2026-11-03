import SwiftData
import XCTest
@testable import ClearNotes

final class SpokenMarksTests: XCTestCase {
    func testSpokenPhrasesBecomeMarksUnlessATapIsNearby() {
        let segments = [
            TranscriptSegment(start: 10, end: 14, text: "Right, action point: Priya to send the rota by Friday."),
            TranscriptSegment(start: 60, end: 64, text: "So the decision is we go live in March."),
            TranscriptSegment(start: 120, end: 124, text: "Can we capture that as an action for Tom?"),
            TranscriptSegment(start: 200, end: 204, text: "Nothing to mark here."),
        ]
        let taps = [MeetingMark(kind: .action, time: 130)]

        let marks = SpokenMarks.find(in: segments, besides: taps)

        XCTAssertEqual(marks.map(\.kind), [.action, .decision])
        XCTAssertEqual(marks.map(\.id), [segments[0].id, segments[1].id], "Same IDs every time the meeting is processed")
        XCTAssertEqual(marks.first?.time, 14)
        XCTAssertTrue(marks.allSatisfy { $0.source == .spoken })
    }
}

final class ActionPolicyTests: XCTestCase {
    func testCommitmentsKeepsClearPromisesAndRequestsOnly() {
        let actions = [
            ExtractedAction(task: "Discuss the rollout", evidence: "We should probably think about the rollout."),
            ExtractedAction(task: "Send the rota", owner: "Priya", evidence: "I'll send the rota over."),
            ExtractedAction(task: "Book the room", evidence: "Can you book the room for Tuesday?"),
            ExtractedAction(task: "Go live in March", evidence: "Can you confirm go live?"),
        ]

        let result = ActionPolicy.suggestions(
            from: actions, decisions: ["Go live in March"], marked: [], duration: 600, setting: .commitments
        )

        XCTAssertEqual(result.map(\.task), ["Send the rota", "Book the room"])
    }

    func testCapIsAboutOnePerFiveMinutesAndMarksUseItUp() {
        XCTAssertEqual(ActionPolicy.cap(forDuration: 3_900), 13)
        XCTAssertEqual(ActionPolicy.cap(forDuration: 60), 2)

        let promises = ["Send the rota", "Book the room", "Order new laptops", "Update the risk log", "Email the supplier"]
            .map { ExtractedAction(task: $0, evidence: "I'll \($0.lowercased()).") }
        let marked = [ExtractedAction(task: "Arrange the away day", markID: UUID())]
        let result = ActionPolicy.suggestions(from: promises, decisions: [], marked: marked, duration: 900, setting: .commitments)
        XCTAssertEqual(result.count, 2, "Three for 15 minutes, less the one marked")
    }

    func testMarkedOnlyHidesSuggestionsAndNothingRepeatsAMark() {
        let actions = [ExtractedAction(task: "Send the rota", owner: "Priya", due: "Friday")]
        XCTAssertTrue(ActionPolicy.suggestions(from: actions, decisions: [], marked: [], duration: 3_600, setting: .markedOnly).isEmpty)

        let marked = [ExtractedAction(task: "Send the rota to everyone", markID: UUID())]
        XCTAssertTrue(ActionPolicy.suggestions(from: actions, decisions: [], marked: marked, duration: 3_600, setting: .everything).isEmpty)
    }
}

final class MarkedMomentTests: XCTestCase {
    private let segments = [
        TranscriptSegment(start: 0, end: 5, text: "The rota is a mess this month.", speakerID: "S1"),
        TranscriptSegment(start: 5, end: 10, text: "I'll send the new rota by Friday.", speakerID: "S2"),
        TranscriptSegment(start: 10, end: 14, text: "Great, thanks.", speakerID: "S1"),
        TranscriptSegment(start: 80, end: 84, text: "We agreed to move the stand-up to ten.", speakerID: "S1"),
    ]
    private let speakers = [
        Speaker(id: "S1", number: 1, name: "Tom"),
        Speaker(id: "S2", number: 2, name: "Priya"),
    ]

    func testTappedActionUsesTheLastPromiseBeforeTheTap() {
        let mark = MeetingMark(kind: .action, time: 15)
        let said = MarkWriter.window(for: mark, in: segments)
        XCTAssertEqual(said.count, 3, "Only what was said around the tap")

        let action = HeuristicEnhancer.markedAction(in: said, before: mark.time, speakers: speakers)

        XCTAssertEqual(action.task, "I'll send the new rota by Friday.")
        XCTAssertEqual(action.owner, "Priya", "The speaker of \"I'll…\" owns it")
        XCTAssertEqual(action.due, "By Friday")
    }

    func testTappedDecisionUsesWhatWasAgreed() {
        let mark = MeetingMark(kind: .decision, time: 86)
        let decision = HeuristicEnhancer.markedDecision(in: MarkWriter.window(for: mark, in: segments), before: mark.time)
        XCTAssertEqual(decision, "We agreed to move the stand-up to ten.")
    }
}

@MainActor
final class MarkedActionsApplyTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    func testMarkedActionsAreOpenAndNotRepeatedWhenNotesAreRewritten() throws {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let segment = TranscriptSegment(start: 0, end: 5, text: "I'll send the new rota by Friday.")
        let meeting = Meeting(title: "Test", segments: [segment])
        container.mainContext.insert(meeting)
        let mark = MeetingMark(kind: .action, time: 6)
        meeting.marks = [mark]
        let marked = MarkedItems(
            actions: [ExtractedAction(task: "Send the new rota", owner: "Priya", due: "By Friday", markID: mark.id)],
            decisions: ["Go live in March"]
        )
        let insights = MeetingInsights(title: nil, summary: "- Rota", decisions: ["We'll go live in March"], actions: [])

        MeetingProcessor.apply(insights, marked: marked, to: meeting)
        MeetingProcessor.apply(insights, marked: marked, to: meeting)

        XCTAssertEqual(meeting.actions.count, 1)
        XCTAssertEqual(meeting.actions.first?.status, .open)
        XCTAssertEqual(meeting.actions.first?.markID, mark.id)
        XCTAssertEqual(meeting.actions.first?.sourceSegmentID, segment.id)
        XCTAssertEqual(meeting.decisions, ["Go live in March"], "A found decision that repeats a marked one is dropped")
    }

    func testDecisionsAndActionsSwap() throws {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let meeting = Meeting(title: "Test")
        container.mainContext.insert(meeting)
        meeting.decisions = ["Book the room"]

        meeting.makeAction(fromDecisionAt: 0)
        XCTAssertTrue(meeting.decisions.isEmpty)
        XCTAssertEqual(meeting.actions.map(\.text), ["Book the room"])

        let action = try XCTUnwrap(meeting.actions.first)
        meeting.makeDecision(from: action)
        XCTAssertEqual(meeting.decisions, ["Book the room"])
        XCTAssertTrue(meeting.actions.isEmpty)
    }
}
