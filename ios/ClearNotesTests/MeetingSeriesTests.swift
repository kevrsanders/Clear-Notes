import SwiftData
import XCTest
@testable import ClearNotes

@MainActor
final class MeetingSeriesTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container
    }

    private func meeting(_ title: String, daysAgo: Double, seriesID: String? = nil, in container: ModelContainer) -> Meeting {
        let meeting = Meeting(title: title, createdAt: now.addingTimeInterval(-daysAgo * 86_400))
        meeting.seriesID = seriesID
        container.mainContext.insert(meeting)
        return meeting
    }

    func testFindsTheLatestEarlierMeetingInTheSameSeries() throws {
        let container = try makeContainer()
        let older = meeting("Weekly check-in", daysAgo: 14, seriesID: "A", in: container)
        let latest = meeting("Weekly check-in", daysAgo: 7, seriesID: "A", in: container)
        let today = meeting("Weekly check-in", daysAgo: 0, seriesID: "A", in: container)
        let otherSeries = meeting("Weekly check-in", daysAgo: 3, seriesID: "B", in: container)

        let found = MeetingSeries.previous(
            seriesID: "A", title: "Weekly check-in", before: now, in: [today, otherSeries, latest, older]
        )

        XCTAssertTrue(found === latest, "Same series, earlier day, most recent; today's never counts")
    }

    func testFallsBackToTheTitleWhenAMeetingHasNoSeries() throws {
        let container = try makeContainer()
        let previous = meeting("Infra & Cyber catch-up", daysAgo: 7, in: container)
        let unrelated = meeting("Board meeting", daysAgo: 2, in: container)
        let all = [previous, unrelated]

        XCTAssertTrue(MeetingSeries.previous(seriesID: "X", title: "infra cyber catch up", before: now, in: all) === previous)
        XCTAssertNil(MeetingSeries.previous(seriesID: nil, title: "Something new", before: now, in: all))
    }

    func testAllMeetingsInASeriesNewestFirst() throws {
        let container = try makeContainer()
        let first = meeting("Weekly check-in", daysAgo: 14, seriesID: "A", in: container)
        let second = meeting("Weekly check-in", daysAgo: 7, seriesID: "A", in: container)
        let today = meeting("Weekly check-in", daysAgo: 0, seriesID: "A", in: container)
        let other = meeting("Board meeting", daysAgo: 3, in: container)

        let series = MeetingSeries.all(like: second, in: [first, other, today, second])

        XCTAssertEqual(series.map(\.createdAt), [today, second, first].map(\.createdAt))
        XCTAssertEqual(MeetingSeries.all(like: other, in: [first, other, today]).count, 1, "A one-off is a series of one")
    }

    func testLinkingToARepeatingEventKeepsItsSeries() throws {
        let container = try makeContainer()
        let recorded = meeting(Meeting.defaultTitle(for: now), daysAgo: 0, in: container)
        recorded.link(to: CalendarMeeting(
            id: "1", title: "Weekly check-in", start: now, end: now.addingTimeInterval(1_800), seriesID: "series-1"
        ))
        XCTAssertEqual(recorded.seriesID, "series-1")
    }

    func testLastTimeLineCountsOpenActions() throws {
        let container = try makeContainer()
        let previous = meeting("Weekly check-in", daysAgo: 7, in: container)
        for status in [ActionStatus.open, .open, .done, .suggested] {
            let action = ActionItem(text: "Task", status: status)
            container.mainContext.insert(action)
            previous.actions.append(action)
        }

        XCTAssertEqual(LastTime.summaryLine(previous), "Last time · \(LastTime.dateText(previous.createdAt)) · 2 open actions")
        XCTAssertEqual(LastTime.actionsText(previous), "2 actions still open")
    }
}
