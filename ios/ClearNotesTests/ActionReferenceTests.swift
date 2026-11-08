import SwiftData
import XCTest
@testable import ClearNotes

@MainActor
final class ActionReferenceTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container.mainContext
    }

    private func add(_ text: String, _ status: ActionStatus, to meeting: Meeting, in context: ModelContext, at offset: TimeInterval) -> ActionItem {
        let action = ActionItem(text: text, status: status)
        action.createdAt = start.addingTimeInterval(offset)
        context.insert(action)
        meeting.actions.append(action)
        return action
    }

    func testInitialsFromTheTitle() {
        XCTAssertEqual(ActionReference.prefix(forTitle: "Weekly check-in"), "WCI")
        XCTAssertEqual(ActionReference.prefix(forTitle: "Budget review"), "BR")
        XCTAssertEqual(ActionReference.prefix(forTitle: "Standup"), "STA", "One word: its first three letters")
        XCTAssertEqual(ActionReference.prefix(forTitle: "Review of the Q3 budget and hosting plans"), "RQBH", "Small words left out, at most four")
        XCTAssertNil(ActionReference.prefix(forTitle: "1:1"))
    }

    func testCatchUpsUseThePersonAndDefaultTitlesTheType() {
        let catchUp = Meeting(title: Meeting.catchUpTitle(with: "Tom Ellis"), createdAt: start)
        catchUp.kind = .catchUp
        catchUp.attendees = ["Tom Ellis"]
        XCTAssertEqual(ActionReference.prefix(for: catchUp), "TE")

        let untitled = Meeting(title: Meeting.defaultTitle(for: start, kind: .meeting), createdAt: start)
        XCTAssertEqual(ActionReference.prefix(for: untitled), "MTG")

        let note = Meeting(title: Meeting.defaultTitle(for: start, kind: .voiceNote), createdAt: start)
        note.kind = .voiceNote
        XCTAssertEqual(ActionReference.prefix(for: note), "VN")
    }

    func testAcceptedActionsAreNumberedInOrderAndKeepTheirReference() throws {
        let context = try makeContext()
        let meeting = Meeting(title: "Weekly check-in", createdAt: start)
        context.insert(meeting)
        let rota = add("Send the revised rota", .open, to: meeting, in: context, at: 1)
        let room = add("Book the room", .suggested, to: meeting, in: context, at: 2)
        let laptops = add("Order new laptops", .open, to: meeting, in: context, at: 3)
        meeting.numberActions()

        XCTAssertEqual(rota.reference, "WCI-1")
        XCTAssertEqual(laptops.reference, "WCI-2")
        XCTAssertNil(room.reference, "A suggestion has no number until it's accepted")

        room.status = .open
        XCTAssertEqual(room.reference, "WCI-3", "Accepted: the next number")

        meeting.title = "Rota and equipment"
        XCTAssertEqual(rota.reference, "WCI-1", "Renaming doesn't change references")

        meeting.actions.removeAll { $0 === room }
        context.delete(room)
        let away = add("Plan the away day", .open, to: meeting, in: context, at: 4)
        meeting.numberActions()
        XCTAssertEqual(away.number, 4, "Numbers aren't reused")

        let dismissed = add("Something else", .suggested, to: meeting, in: context, at: 5)
        dismissed.status = .dismissed
        XCTAssertNil(dismissed.number)
    }

    func testMinutesListActionsByReference() {
        let lines = MinutesFormat.lines(from: """
            Weekly check-in
            Summary of actions
            WCI-3. Share the rota — Priya Sharma
            A2. Book a room
            """)
        XCTAssertEqual(lines[2], .summaryAction(number: "WCI-3", text: "Share the rota — Priya Sharma"))
        XCTAssertEqual(lines[3], .summaryAction(number: "A2", text: "Book a room"))
    }
}
