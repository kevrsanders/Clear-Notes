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
}
