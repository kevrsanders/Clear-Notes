import XCTest
@testable import ClearNotes

final class CalendarScreenTests: XCTestCase {
    func testDaysHandedToTheCalendarCarryItsCalendar() {
        let calendar = Calendar(identifier: .gregorian)
        let day = DateComponents(year: 2026, month: 11, day: 9)

        let handed = MeetingCalendar.withCalendar(day, calendar)

        XCTAssertEqual(handed?.calendar?.identifier, .gregorian)
        XCTAssertEqual(handed?.year, 2026)
        XCTAssertEqual(handed?.month, 11)
        XCTAssertEqual(handed?.day, 9)
        XCTAssertNil(MeetingCalendar.withCalendar(nil, calendar))
        XCTAssertNil(MeetingCalendar.withCalendar(DateComponents(year: 2026, month: 11), calendar), "Not a whole day")
    }

    func testDaysAreLookedUpByNumberWhateverElseTheirComponentsSay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let meeting = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 15, minute: 4))!

        // As the screen works the day out, and as the calendar view asks about it.
        let fromMeeting = MeetingCalendar.day(of: meeting, in: calendar)
        var fromView = DateComponents(calendar: calendar, era: 1, year: 2026, month: 11, day: 5)
        fromView.isLeapMonth = false

        XCTAssertEqual(MeetingCalendar.key(fromMeeting), 20_261_105)
        XCTAssertEqual(MeetingCalendar.key(fromView), 20_261_105)
        XCTAssertNil(MeetingCalendar.key(DateComponents(year: 2026, month: 11)))
    }
}
