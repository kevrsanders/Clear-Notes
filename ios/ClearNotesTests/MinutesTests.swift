import SwiftData
import XCTest
@testable import ClearNotes

final class MinutesDocumentTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    private func part(_ title: String?, from start: TimeInterval, to end: TimeInterval) -> MinutesWriter.Part {
        MinutesWriter.Part(title: title, start: start, end: end, transcript: "", segments: [], keyPoints: [])
    }

    func testItemsAreNumberedWithDecisionsAndActionsUnderWhereTheyWereSaid() {
        let input = MinutesWriter.Input(
            title: "Weekly check-in",
            start: start,
            duration: 1_800,
            present: ["Priya Sharma", "Tom Ellis"],
            unnamedSpeakers: 1,
            parts: [part("Rota changes", from: 0, to: 600), part("Budget", from: 600, to: 1_800)],
            decisions: [
                MinutesWriter.Decision(text: "the new rota starts on 1 December", time: 120),
                MinutesWriter.Decision(text: "Hold the budget review until January", time: nil),
            ],
            actions: [
                MinutesWriter.Action(text: "Send the revised budget to finance", owner: "Tom Ellis", due: "by Friday", isDone: false, time: 900),
                MinutesWriter.Action(text: "Share the new rota.", owner: "Priya Sharma", due: nil, isDone: true, time: 200),
            ],
            speakers: []
        )
        let items = [
            MinutesWriter.Item(title: "Rota changes", points: ["Priya reported that the new rota was ready", "Concerns were raised about weekend cover."]),
            MinutesWriter.Item(title: "Budget", points: ["it was noted that spending was on track"]),
        ]

        let lines = MinutesWriter.document(input, items: items, locale: Locale(identifier: "en_GB"))
            .components(separatedBy: "\n")

        XCTAssertEqual(lines[0], "Weekly check-in")
        XCTAssertTrue(lines[1].hasPrefix("Minutes of the meeting held on "))
        XCTAssertTrue(lines.contains("Present: Priya Sharma, Tom Ellis and 1 other"))
        XCTAssertEqual(Array(lines.drop { $0 != "1. Rota changes" }.prefix(5)), [
            "1. Rota changes",
            "1.1 Priya reported that the new rota was ready.",
            "1.2 Concerns were raised about weekend cover.",
            "Agreed: The new rota starts on 1 December.",
            "Action: Share the new rota — Priya Sharma",
        ])
        XCTAssertEqual(Array(lines.drop { $0 != "2. Budget" }.prefix(3)), [
            "2. Budget",
            "2.1 It was noted that spending was on track.",
            "Action: Send the revised budget to finance — Tom Ellis, by Friday",
        ])
        XCTAssertEqual(Array(lines.drop { $0 != "3. Other decisions and actions" }.prefix(2)), [
            "3. Other decisions and actions",
            "Agreed: Hold the budget review until January.",
        ])
        XCTAssertEqual(Array(lines.suffix(3)), [
            "Summary of actions",
            "A1. Send the revised budget to finance — Tom Ellis, by Friday",
            "A2. Share the new rota — Priya Sharma (done)",
        ])
    }

    func testWithOnePartEverythingGoesUnderIt() {
        XCTAssertEqual(MinutesWriter.itemIndex(for: nil, in: [part(nil, from: 0, to: 60)]), 0)
        let parts = [part("A", from: 0, to: 60), part("B", from: 60, to: 120)]
        XCTAssertNil(MinutesWriter.itemIndex(for: nil, in: parts))
        XCTAssertEqual(MinutesWriter.itemIndex(for: 30, in: parts), 0)
        XCTAssertEqual(MinutesWriter.itemIndex(for: 90, in: parts), 1)
    }

    func testPresentLine() {
        XCTAssertEqual(MinutesWriter.presentLine(names: ["Priya Sharma"], unnamed: 0), "Present: Priya Sharma")
        XCTAssertEqual(MinutesWriter.presentLine(names: [], unnamed: 3), "Present: 3 people (speakers not named yet)")
        XCTAssertNil(MinutesWriter.presentLine(names: [], unnamed: 0), "No line when voices weren't separated")
    }

    func testTheModelsAnswerIsReadWithOrWithoutAHeading() {
        let answer = """
            **Heading: Rota changes**
            - Priya reported that the new rota was ready.
            - Concerns were raised about weekend cover.
            """
        let parsed = MinutesWriter.parse(answer, wantsTitle: true)
        XCTAssertEqual(parsed.title, "Rota changes")
        XCTAssertEqual(parsed.points, [
            "Priya reported that the new rota was ready.",
            "Concerns were raised about weekend cover.",
        ])

        let html = "<ul><li>Tom said the budget was on track.</li><li>It was noted that hosting costs had risen.</li></ul>"
        let fromHTML = MinutesWriter.parse(html, wantsTitle: false)
        XCTAssertNil(fromHTML.title)
        XCTAssertEqual(fromHTML.points, ["Tom said the budget was on track.", "It was noted that hosting costs had risen."])
    }

    func testLinesAreRecognisedForStyling() {
        let text = """
            Weekly check-in
            Minutes of the meeting held on Tuesday 3 November 2026, 10:00 to 10:30

            Present: Priya Sharma
            1. Rota changes
            1.1 Priya reported that the rota was ready.
            Agreed: The rota starts on 1 December.
            Action: Share the rota — Priya Sharma
            Summary of actions
            A1. Share the rota — Priya Sharma
            A note the user added.
            """

        XCTAssertEqual(MinutesFormat.lines(from: text), [
            .title("Weekly check-in"),
            .subtitle("Minutes of the meeting held on Tuesday 3 November 2026, 10:00 to 10:30"),
            .labelled(label: "Present", text: "Priya Sharma"),
            .heading(number: "1", text: "Rota changes"),
            .point(number: "1.1", text: "Priya reported that the rota was ready."),
            .agreed("The rota starts on 1 December."),
            .action("Share the rota — Priya Sharma"),
            .section("Summary of actions"),
            .summaryAction(number: "A1", text: "Share the rota — Priya Sharma"),
            .paragraph("A note the user added."),
        ])
    }
}

@MainActor
final class MinutesInputTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    func testTopicsBecomeItemsAndOnlyAcceptedActionsAreIncluded() throws {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let rota = TranscriptSegment(start: 5, end: 9, text: "The new rota is ready.", speakerID: "S1")
        let budget = TranscriptSegment(start: 400, end: 404, text: "I'll send the budget to finance.", speakerID: "S2")
        let meeting = Meeting(title: "Weekly check-in", segments: [rota, budget])
        container.mainContext.insert(meeting)
        meeting.speakers = [Speaker(id: "S1", number: 1, name: "Priya Sharma"), Speaker(id: "S2", number: 2)]
        meeting.topics = [
            Topic(title: "Rota changes", start: 0, end: 300, points: ["The rota is ready"]),
            Topic(title: "Budget", start: 300, end: 600),
        ]
        let accepted = ActionItem(text: "Send the budget to finance", status: .open, sourceSegmentID: budget.id)
        let suggested = ActionItem(text: "Book a room", status: .suggested)
        for action in [accepted, suggested] {
            container.mainContext.insert(action)
            meeting.actions.append(action)
        }

        let input = MinutesWriter.Input(meeting)

        XCTAssertEqual(input.parts.map(\.title), ["Rota changes", "Budget"])
        XCTAssertEqual(input.parts[0].transcript, "[0:05] Priya Sharma: The new rota is ready.")
        XCTAssertEqual(input.parts[1].transcript, "[6:40] Speaker 2: I'll send the budget to finance.")
        XCTAssertEqual(input.present, ["Priya Sharma"])
        XCTAssertEqual(input.unnamedSpeakers, 1)
        XCTAssertEqual(input.actions.map(\.text), ["Send the budget to finance"])
        XCTAssertEqual(input.actions.first?.time, 400)
    }
}
