import XCTest
@testable import ClearNotes

final class FollowUpAndTopicTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_793_000_000)

    private var snapshot: MeetingSnapshot {
        MeetingSnapshot(
            title: "Website relaunch check-in",
            date: date,
            summary: "- Content audit is 80% complete\n- Launch moved to March",
            decisions: ["Move the launch to March"],
            topics: [Topic(title: "Launch timing", start: 400, end: 845)],
            actions: [
                .init(text: "Send the revised page list", owner: "Priya", due: "By Friday", isDone: false),
                .init(text: "Update the risk log", owner: nil, due: nil, isDone: false),
                .init(text: "Share the audit spreadsheet", owner: "Tom", due: nil, isDone: true),
            ],
            people: ["Priya", "Tom"]
        )
    }

    // MARK: - Follow-ups

    func testActionListShowsOwnersDueDatesAndDoneItems() {
        let text = FollowUpWriter.actionList(snapshot)
        XCTAssertTrue(text.contains("☐ Send the revised page list — Priya, By Friday"))
        XCTAssertTrue(text.contains("☐ Update the risk log\n"))
        XCTAssertTrue(text.contains("Done:\n☑ Share the audit spreadsheet"))
    }

    func testEmailHasSubjectSummaryDecisionsAndNextSteps() {
        let text = FollowUpWriter.email(snapshot)
        XCTAssertTrue(text.hasPrefix("Subject: Follow-up: Website relaunch check-in"))
        XCTAssertTrue(text.contains("• Content audit is 80% complete"))
        XCTAssertTrue(text.contains("What we agreed\n• Move the launch to March"))
        XCTAssertTrue(text.contains("• Priya: Send the revised page list (by friday)"))
        XCTAssertFalse(text.contains("Share the audit spreadsheet"), "Done actions aren't next steps")
    }

    func testProjectPlanGroupsWorkByOwnerWithUnassignedLast() throws {
        let text = FollowUpWriter.projectPlan(snapshot)
        XCTAssertTrue(text.contains("Goal\nContent audit is 80% complete"))
        let priya = try XCTUnwrap(text.range(of: "Priya\n  • Send the revised page list"))
        let unassigned = try XCTUnwrap(text.range(of: "Unassigned\n  • Update the risk log"))
        XCTAssertLessThan(priya.lowerBound, unassigned.lowerBound)
        XCTAssertTrue(text.contains("Timeline\n• By Friday: Send the revised page list"))
        XCTAssertTrue(text.contains("Areas discussed\n• Launch timing"))
    }

    // MARK: - Talk time

    func testTalkTimeSumsBySpeakerAndIgnoresUnknown() {
        var a = TranscriptSegment(start: 0, end: 30, text: "a")
        a.speakerID = "S1"
        var b = TranscriptSegment(start: 30, end: 40, text: "b")
        b.speakerID = "S2"
        var c = TranscriptSegment(start: 40, end: 70, text: "c")
        c.speakerID = "S1"
        let unknown = TranscriptSegment(start: 70, end: 100, text: "d")

        let totals = TalkTime.bySpeaker([a, b, c, unknown])
        XCTAssertEqual(totals, ["S1": 60, "S2": 10])
        let shares = TalkTime.shares(totals)
        XCTAssertEqual(try XCTUnwrap(shares["S1"]), 60.0 / 70.0, accuracy: 0.0001)
        XCTAssertTrue(TalkTime.shares([:]).isEmpty)
    }

    // MARK: - Topics (basic extraction)

    func testShortMeetingsGetNoTopics() {
        let segments = [TranscriptSegment(start: 0, end: 240, text: "Budget budget hosting hosting.")]
        XCTAssertTrue(HeuristicEnhancer.topics(in: segments).isEmpty)
    }

    func testAShortMeetingIsOneTopicSoItsPageHasTopics() async throws {
        let segments = [
            TranscriptSegment(start: 0, end: 60, text: "The budget review comes first and the budget looks healthy for the quarter."),
            TranscriptSegment(start: 60, end: 120, text: "We also need to talk about the budget for training next year please."),
        ]
        let insights = try await HeuristicEnhancer().enhance(segments: segments, speakers: [], userNotes: "")
        XCTAssertEqual(insights.topics.count, 1)
        XCTAssertEqual(insights.topics.first?.title, "Budget")
        XCTAssertEqual(insights.topics.first?.start, 0)
        XCTAssertEqual(insights.topics.first?.end, 120)
        XCTAssertEqual(insights.topics.first?.points.count, 2)
    }

    func testTopicsSplitIntoWindowsTitledByKeywords() {
        let segments = [
            TranscriptSegment(start: 0, end: 200, text: "The budget review is first. The budget looks healthy for the quarter overall."),
            TranscriptSegment(start: 200, end: 290, text: "Training budget is the main budget question we still have."),
            TranscriptSegment(start: 310, end: 500, text: "Next the hosting contract. The hosting renewal is due before December."),
            TranscriptSegment(start: 500, end: 640, text: "Hosting costs went up, so the contract needs checking soon."),
        ]
        let topics = HeuristicEnhancer.topics(in: segments)
        XCTAssertEqual(topics.count, 2)
        XCTAssertEqual(topics.first?.title, "Budget")
        XCTAssertEqual(topics.first?.start, 0)
        XCTAssertEqual(topics.first?.end, 290)
        XCTAssertEqual(topics.last?.title, "Hosting and contract")
        XCTAssertEqual(topics.last?.start, 310)
    }

    func testKeywordsSkipFillerAndRareWords() {
        XCTAssertEqual(
            HeuristicEnhancer.keywords(in: "Yeah, really really think the roadmap matters. Roadmap again, yeah.", limit: 2),
            ["roadmap"]
        )
    }
}
