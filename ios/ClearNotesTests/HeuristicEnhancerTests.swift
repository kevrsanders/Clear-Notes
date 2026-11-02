import XCTest
@testable import ClearNotes

final class HeuristicEnhancerTests: XCTestCase {
    private let enhancer = HeuristicEnhancer()

    private func segments(_ texts: String...) -> [TranscriptSegment] {
        texts.enumerated().map { index, text in
            TranscriptSegment(start: TimeInterval(index * 30), end: TimeInterval(index * 30 + 25), text: text)
        }
    }

    func testExtractsActionWithOwnerAndDueDate() async throws {
        let insights = try await enhancer.enhance(
            segments: segments("Thanks everyone. Priya will send the revised budget by Friday."),
            speakers: [],
            userNotes: ""
        )
        XCTAssertEqual(insights.actions.count, 1)
        XCTAssertEqual(insights.actions.first?.owner, "Priya")
        XCTAssertEqual(insights.actions.first?.due, "By Friday")
        XCTAssertEqual(insights.actions.first?.evidence, "Priya will send the revised budget by Friday.")
    }

    func testExtractsDecisionsSeparatelyFromActions() async throws {
        let insights = try await enhancer.enhance(
            segments: segments("We agreed to move the launch to March.", "Tom needs to update the risk log."),
            speakers: [],
            userNotes: ""
        )
        XCTAssertEqual(insights.decisions, ["We agreed to move the launch to March."])
        XCTAssertEqual(insights.actions.map(\.task), ["Tom needs to update the risk log."])
        XCTAssertEqual(insights.actions.first?.owner, "Tom")
    }

    func testPronounsAreNotOwners() {
        XCTAssertNil(HeuristicEnhancer.owner(in: "We will look at it again."))
        XCTAssertNil(HeuristicEnhancer.owner(in: "I'll pick that up."))
    }

    func testDueDateNeedsMoreThanAWord() {
        XCTAssertNil(HeuristicEnhancer.due(in: "It was a busy week."))
        XCTAssertEqual(HeuristicEnhancer.due(in: "Let's review it next week."), "Next week")
        XCTAssertEqual(HeuristicEnhancer.due(in: "Done by the end of the month please."), "By the end of the month")
    }

    func testMarkedNoteLinesBecomeActionsAndDecisions() async throws {
        let insights = try await enhancer.enhance(
            segments: [],
            speakers: [],
            userNotes: "Action: [2:10] Book the boardroom\nDecision: Use the new template\nGeneral chat"
        )
        XCTAssertEqual(insights.actions.map(\.task), ["[2:10] Book the boardroom"])
        XCTAssertEqual(insights.decisions, ["Use the new template"])
    }

    func testDuplicateActionsAreMerged() async throws {
        let insights = try await enhancer.enhance(
            segments: segments("Can you send the slides?", "can you send the slides?"),
            speakers: [],
            userNotes: ""
        )
        XCTAssertEqual(insights.actions.count, 1)
    }

    func testSummaryPrefersUserNotes() {
        let summary = HeuristicEnhancer.summary(segments: [], userNotes: "Budget is on track\n- Hiring paused")
        XCTAssertEqual(summary, "- Budget is on track\n- Hiring paused")
    }

    func testFirstPersonCommitmentIsOwnedByNamedSpeaker() async throws {
        var segment = TranscriptSegment(start: 0, end: 5, text: "I'll send the revised page list by Friday.")
        segment.speakerID = "S1"
        let insights = try await enhancer.enhance(
            segments: [segment],
            speakers: [Speaker(id: "S1", number: 1, name: "Priya")],
            userNotes: ""
        )
        XCTAssertEqual(insights.actions.first?.owner, "Priya")
    }

    func testUnnamedSpeakerIsNotUsedAsOwner() async throws {
        var segment = TranscriptSegment(start: 0, end: 5, text: "I'll update the risk log.")
        segment.speakerID = "S2"
        let insights = try await enhancer.enhance(
            segments: [segment],
            speakers: [Speaker(id: "S2", number: 2)],
            userNotes: ""
        )
        XCTAssertEqual(insights.actions.count, 1)
        XCTAssertNil(insights.actions.first?.owner)
    }

    func testCuesMatchWholeWordsOnly() async throws {
        let insights = try await enhancer.enhance(
            segments: segments("The taxi will arrive at noon."),
            speakers: [],
            userNotes: ""
        )
        XCTAssertTrue(insights.actions.isEmpty)
    }
}
