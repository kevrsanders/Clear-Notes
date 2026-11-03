import SwiftData
import XCTest
@testable import ClearNotes

final class CalendarMeetingPickerTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var day: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_793_000_000)) }

    private func at(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        day.addingTimeInterval(TimeInterval(dayOffset * 86_400 + hour * 3_600 + minute * 60))
    }

    private func event(_ title: String, _ start: Date, _ end: Date, attendees: [String] = []) -> CalendarMeeting {
        CalendarMeeting(id: title, title: title, start: start, end: end, attendees: attendees)
    }

    private var backToBack: [CalendarMeeting] {
        [
            event("Board", at(10), at(11)),
            event("Project", at(11), at(12)),
        ]
    }

    func testPicksTheMeetingInProgress() {
        XCTAssertEqual(CalendarMeetingPicker.current(in: backToBack, at: at(10, 20))?.title, "Board")
    }

    func testJustBeforeBackToBackMeetingsPicksTheNextOne() {
        XCTAssertEqual(CalendarMeetingPicker.current(in: backToBack, at: at(10, 55))?.title, "Project")
    }

    func testOnlyLooksTenMinutesAhead() {
        XCTAssertNil(CalendarMeetingPicker.current(in: backToBack, at: at(9, 45)))
        XCTAssertEqual(CalendarMeetingPicker.current(in: backToBack, at: at(9, 52))?.title, "Board")
        XCTAssertNil(CalendarMeetingPicker.current(in: backToBack, at: at(12, 5)))
    }

    func testIgnoresAllDayCancelledAndDeclinedEvents() {
        var allDay = event("Annual leave", at(0), at(0, dayOffset: 1))
        allDay.isAllDay = true
        var declined = event("Declined", at(10), at(11))
        declined.isCancelledOrDeclined = true
        let meetings = [allDay, declined, event("Huddle", at(10, 30), at(10, 45))]

        XCTAssertNil(CalendarMeetingPicker.current(in: meetings, at: at(10, 5)))
        XCTAssertEqual(CalendarMeetingPicker.current(in: meetings, at: at(10, 25))?.title, "Huddle")
    }

    func testDayLongTimedBlocksAreIgnoredLikeAllDayEvents() {
        let meetings = [
            event("Working from home", at(9), at(17)),
            event("Leave", at(0), at(0, dayOffset: 2)),
            event("Workshop", at(9), at(13)),
        ]
        XCTAssertEqual(CalendarMeetingPicker.current(in: meetings, at: at(9, 5))?.title, "Workshop")
        XCTAssertNil(CalendarMeetingPicker.current(in: meetings, at: at(14)))
        XCTAssertNil(CalendarMeetingPicker.next(in: [event("Training day", at(10), at(16, 30))], after: at(8), calendar: calendar))
    }

    func testOverlappingMeetingsThatStartTogetherPreferTheOneWithPeople() {
        let meetings = [
            event("Focus time", at(14), at(15)),
            event("Check-in", at(14), at(14, 30), attendees: ["Alex Morgan"]),
        ]
        XCTAssertEqual(CalendarMeetingPicker.current(in: meetings, at: at(14, 2))?.title, "Check-in")
    }

    func testMeetingsWithPeopleComeBeforeBlocks() {
        let day = [
            event("WFH", at(8), at(8, 30)),
            event("Report writing", at(8, 15), at(8, 50)),
            event("CAB", at(10), at(11), attendees: ["Alex Morgan"]),
            event("Focus time", at(13), at(14)),
        ]
        let early = CalendarMeetingPicker.upNext(in: day, at: at(7, 13), calendar: calendar)
        XCTAssertEqual(early?.event.title, "CAB")
        XCTAssertEqual(early?.isNow, false)

        // With no meeting left today, a block happening now is still offered.
        let afternoon = CalendarMeetingPicker.upNext(in: day, at: at(13, 10), calendar: calendar)
        XCTAssertEqual(afternoon?.event.title, "Focus time")
        XCTAssertEqual(afternoon?.isNow, true)
    }

    func testABlockOnlyWinsWhenItStartsMuchNearer() {
        let meetings = [
            event("CAB", at(10), at(11), attendees: ["Alex Morgan"]),
            event("Prep", at(10, 25), at(10, 40)),
            event("Walk-round", at(10, 50), at(11, 30)),
        ]
        // A block starting in 5 minutes doesn't beat a meeting that started 20 minutes ago.
        XCTAssertEqual(CalendarMeetingPicker.current(in: meetings, at: at(10, 20))?.title, "CAB")
        // A block that started 2 minutes ago beats a meeting that's 52 minutes in.
        XCTAssertEqual(CalendarMeetingPicker.current(in: meetings, at: at(10, 52))?.title, "Walk-round")
    }

    func testNextIsLaterTheSameDay() {
        let meetings = backToBack + [event("Tomorrow", at(9, dayOffset: 1), at(10, dayOffset: 1))]
        XCTAssertEqual(CalendarMeetingPicker.next(in: meetings, after: at(10, 20), calendar: calendar)?.title, "Project")
        XCTAssertNil(CalendarMeetingPicker.next(in: meetings, after: at(11, 30), calendar: calendar))
    }
}

final class PersonNameTests: XCTestCase {
    func testDirectoryNamesBecomeEverydayNames() {
        XCTAssertEqual(PersonName.display(name: "SMITH, Jane (Example Trust)"), "Jane Smith")
        XCTAssertEqual(PersonName.display(name: "O'BRIEN, Sean"), "Sean O'Brien")
        XCTAssertEqual(PersonName.display(name: "Mary SMITH-JONES [Contractor]"), "Mary Smith-Jones")
        XCTAssertEqual(PersonName.display(name: "Dr Ann Lee"), "Dr Ann Lee")
        XCTAssertEqual(PersonName.display(name: "  Alex  "), "Alex")
    }

    func testFallsBackToTheEmailAddress() {
        XCTAssertEqual(PersonName.display(name: nil, email: "jane.smith2@example.org"), "Jane Smith")
        XCTAssertEqual(PersonName.display(name: "sam_taylor@example.org", email: nil), "Sam Taylor")
        XCTAssertEqual(PersonName.display(name: "", email: "alex@example.org"), "Alex")
        XCTAssertNil(PersonName.display(name: nil, email: nil))
    }
}

final class CalendarChoiceTests: XCTestCase {
    func testOnlyYourOwnCalendarsAreOnByDefault() {
        XCTAssertTrue(CalendarChoice.isOnByDefault(title: "Calendar", isMain: false))
        XCTAssertTrue(CalendarChoice.isOnByDefault(title: "Home", isMain: true))
        XCTAssertFalse(CalendarChoice.isOnByDefault(title: "SMITH, Jane (Example Trust)", isMain: false))
        XCTAssertFalse(CalendarChoice.isOnByDefault(title: "Team rota", isMain: false))
    }

    func testSharedCalendarNamesAreTidied() {
        XCTAssertEqual(CalendarChoice.displayName("SMITH, Jane (Example Trust)"), "Jane Smith")
        XCTAssertEqual(CalendarChoice.displayName("Lee, Sam"), "Sam Lee")
        XCTAssertEqual(CalendarChoice.displayName("Team rota (Ward 4)"), "Team rota (Ward 4)")
    }
}

final class TeamsLinkTests: XCTestCase {
    func testFindsTheJoinLinkInTheInvite() {
        let link = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=abc"
        let notes = "Microsoft Teams meeting\nJoin on your computer: <\(link)>\nMeeting ID: 123"
        XCTAssertEqual(TeamsLink.find(in: [nil, "Room 4", notes])?.absoluteString, link)
        XCTAssertEqual(
            TeamsLink.find(in: ["Join: https://teams.microsoft.com/meet/123456?p=xyz."])?.absoluteString,
            "https://teams.microsoft.com/meet/123456?p=xyz"
        )
    }

    func testIgnoresOtherLinks() {
        XCTAssertNil(TeamsLink.find(in: ["https://example.org/meet/123", nil, "Room 4"]))
    }
}

final class OwnerMatcherTests: XCTestCase {
    private let invited = ["Priya Sharma", "Tom Lee", "Sam Taylor", "Sam Green"]

    func testFirstNameBecomesTheInvitedPersonsFullName() {
        XCTAssertEqual(OwnerMatcher.match("Priya", speakers: [], attendees: invited), "Priya Sharma")
        XCTAssertEqual(OwnerMatcher.match("tom lee", speakers: [], attendees: invited), "Tom Lee")
    }

    func testAmbiguousOrUnknownOwnersAreLeftAlone() {
        XCTAssertEqual(OwnerMatcher.match("Sam", speakers: [], attendees: invited), "Sam")
        XCTAssertEqual(OwnerMatcher.match("Jo", speakers: [], attendees: invited), "Jo")
    }

    func testSpeakerNamesComeFirst() {
        XCTAssertEqual(OwnerMatcher.match("priya", speakers: ["Priya"], attendees: invited), "Priya")
    }
}

@MainActor
final class MeetingCalendarLinkTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    private func makeMeeting() throws -> Meeting {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let meeting = Meeting(title: Meeting.defaultTitle(for: .now))
        container.mainContext.insert(meeting)
        return meeting
    }

    func testLinkingTakesTitlePeopleAndTeamsLink() throws {
        let meeting = try makeMeeting()
        let event = CalendarMeeting(
            id: "1", title: "Website relaunch", start: .now, end: .now.addingTimeInterval(1_800),
            attendees: ["Priya Sharma", "Tom Lee"],
            teamsJoinURL: URL(string: "https://teams.microsoft.com/meet/123")
        )
        meeting.link(to: event)

        XCTAssertEqual(meeting.title, "Website relaunch")
        XCTAssertEqual(meeting.attendees, ["Priya Sharma", "Tom Lee"])
        XCTAssertEqual(meeting.teamsJoinURL, "https://teams.microsoft.com/meet/123")
    }

    func testAnUntitledEventKeepsTheDefaultTitle() throws {
        let meeting = try makeMeeting()
        let title = meeting.title
        meeting.link(to: CalendarMeeting(id: "2", title: "", start: .now, end: .now.addingTimeInterval(600)))
        XCTAssertEqual(meeting.title, title)
    }
}
