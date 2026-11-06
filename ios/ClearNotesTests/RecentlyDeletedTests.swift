import SwiftData
import XCTest
@testable import ClearNotes

@MainActor
final class RecentlyDeletedTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    /// 1 November 2026, 10:00 UTC.
    private let deletedAt = Date(timeIntervalSince1970: 1_793_527_200)

    func testAMeetingIsKeptForAWeek() {
        let day: TimeInterval = 86_400
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt, now: deletedAt.addingTimeInterval(2 * 3_600), calendar: calendar), 7)
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt, now: deletedAt.addingTimeInterval(6 * day), calendar: calendar), 1)
        XCTAssertEqual(RecentlyDeleted.daysLeft(deletedAt, now: deletedAt.addingTimeInterval(7 * day - 3_600), calendar: calendar), 0)
        XCTAssertFalse(RecentlyDeleted.isExpired(deletedAt, now: deletedAt.addingTimeInterval(7 * day - 1)))
        XCTAssertTrue(RecentlyDeleted.isExpired(deletedAt, now: deletedAt.addingTimeInterval(7 * day)))

        XCTAssertEqual(RecentlyDeleted.statusLine(deletedAt, now: deletedAt.addingTimeInterval(60), calendar: calendar), "Deleted today · 7 days left")
        XCTAssertTrue(RecentlyDeleted.statusLine(deletedAt, now: deletedAt.addingTimeInterval(6 * day), calendar: calendar).hasSuffix("· 1 day left"))
    }

    func testDeletingMovesToRecentlyDeletedAndRestoreBringsItBack() throws {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let context = container.mainContext
        let meeting = Meeting(title: "Weekly check-in")
        context.insert(meeting)

        meeting.moveToRecentlyDeleted(at: deletedAt)
        let live = try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.deletedAt == nil }))
        XCTAssertTrue(live.isEmpty, "A deleted meeting leaves the lists")
        XCTAssertEqual(meeting.deletedAt, deletedAt)

        meeting.restoreFromRecentlyDeleted()
        XCTAssertNil(meeting.deletedAt)
        XCTAssertEqual(try context.fetch(FetchDescriptor<Meeting>(predicate: #Predicate { $0.deletedAt == nil })).count, 1)
    }

    func testOnlyMeetingsDeletedAWeekAgoAreDeletedForGood() throws {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let context = container.mainContext
        let kept = Meeting(title: "Budget review")
        let recent = Meeting(title: "Rota planning")
        let old = Meeting(title: "Team huddle")
        for meeting in [kept, recent, old] {
            context.insert(meeting)
        }
        recent.moveToRecentlyDeleted(at: deletedAt.addingTimeInterval(6 * 86_400))
        old.moveToRecentlyDeleted(at: deletedAt)

        RecentlyDeleted.purgeExpired(in: context, now: deletedAt.addingTimeInterval(7 * 86_400 + 60))

        let titles = try context.fetch(FetchDescriptor<Meeting>()).map(\.title).sorted()
        XCTAssertEqual(titles, ["Budget review", "Rota planning"])
    }

    func testUndoRestoresTheLastDeletedMeeting() {
        let meeting = Meeting(title: "Weekly check-in")
        meeting.moveToRecentlyDeleted(at: deletedAt)
        let undo = DeletionUndo()
        let before = undo.token
        undo.didDelete(meeting)
        XCTAssertNotEqual(undo.token, before)
        undo.undo()
        XCTAssertNil(meeting.deletedAt)
        XCTAssertNil(undo.meeting)
    }
}
