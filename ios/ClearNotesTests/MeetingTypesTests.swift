import SwiftData
import XCTest
@testable import ClearNotes

@MainActor
final class MeetingTypesTests: XCTestCase {
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

    private func recording(_ kind: MeetingKind, _ title: String, with person: String? = nil, daysAgo: Double = 0) -> Meeting {
        let meeting = Meeting(title: title, createdAt: start.addingTimeInterval(-daysAgo * 86_400))
        meeting.kind = kind
        if let person { meeting.attendees = [person] }
        return meeting
    }

    func testDefaultTitlesFollowTheType() {
        let voiceNote = Meeting(title: Meeting.defaultTitle(for: start, kind: .voiceNote), createdAt: start)
        XCTAssertTrue(voiceNote.title.hasPrefix("Voice note · "))
        XCTAssertTrue(voiceNote.hasDefaultTitle)
        voiceNote.title = "Ideas for the rota handover"
        XCTAssertFalse(voiceNote.hasDefaultTitle)
        XCTAssertEqual(Meeting(title: "Weekly check-in").kind, .meeting, "Recordings made before types existed are meetings")
    }

    func testACatchUpIsNamedAfterWhoItWasWith() {
        let meeting = recording(.catchUp, Meeting.defaultTitle(for: start, kind: .catchUp))
        meeting.setCatchUpPerson("Tom Ellis")
        XCTAssertEqual(meeting.title, "Catch-up with Tom Ellis")
        XCTAssertEqual(meeting.catchUpPerson, "Tom Ellis")

        meeting.setCatchUpPerson("Priya Sharma")
        XCTAssertEqual(meeting.title, "Catch-up with Priya Sharma", "A title Clear Notes gave follows the person")

        meeting.title = "Rota chat"
        meeting.setCatchUpPerson("Sam Lee")
        XCTAssertEqual(meeting.title, "Rota chat", "A title the user chose is kept")
        XCTAssertEqual(meeting.catchUpPerson, "Sam Lee")

        meeting.setCatchUpPerson(nil)
        XCTAssertNil(meeting.catchUpPerson)
    }

    func testChangingTypeKeepsChosenTitlesAndMakesSuggestionsToDos() throws {
        let context = try makeContext()
        let meeting = Meeting(title: Meeting.defaultTitle(for: start), createdAt: start)
        context.insert(meeting)
        let suggested = ActionItem(text: "Draft a handover checklist", status: .suggested)
        context.insert(suggested)
        meeting.actions.append(suggested)

        meeting.changeKind(to: .voiceNote)
        XCTAssertEqual(meeting.kind, .voiceNote)
        XCTAssertEqual(meeting.title, Meeting.defaultTitle(for: start, kind: .voiceNote))
        XCTAssertEqual(suggested.status, .open, "A voice note's to-dos are the user's own")

        meeting.title = "Handover ideas"
        meeting.changeKind(to: .catchUp)
        XCTAssertEqual(meeting.kind, .catchUp)
        XCTAssertEqual(meeting.title, "Handover ideas")
    }

    func testLinkingToADiaryMeetingMakesItADiaryMeeting() {
        let meeting = recording(.voiceNote, Meeting.defaultTitle(for: start, kind: .voiceNote))
        XCTAssertFalse(meeting.isFromDiary)
        XCTAssertTrue(MeetingFilter.voiceNotes.matches(meeting))

        let event = CalendarMeeting(id: "E1-1", title: "Weekly check-in", start: start, end: start.addingTimeInterval(1_800), attendees: ["Priya Sharma"])
        meeting.link(to: event)

        XCTAssertEqual(meeting.kind, .meeting)
        XCTAssertEqual(meeting.calendarEventID, "E1-1")
        XCTAssertEqual(meeting.title, "Weekly check-in")
        XCTAssertTrue(meeting.isFromDiary)
        XCTAssertTrue(MeetingFilter.diary.matches(meeting))
        XCTAssertFalse(MeetingFilter.voiceNotes.matches(meeting))
        XCTAssertTrue(MeetingFilter.all.matches(meeting))
    }

    func testCatchUpsWithTheSamePersonFormASeriesAndVoiceNotesNever() {
        let older = recording(.catchUp, "Catch-up with Tom Ellis", with: "Tom Ellis", daysAgo: 7)
        let renamed = recording(.catchUp, "Rota chat", with: "tom ellis", daysAgo: 3)
        let current = recording(.catchUp, "Catch-up with Tom Ellis", with: "Tom Ellis")
        let otherPerson = recording(.catchUp, "Catch-up with Priya Sharma", with: "Priya Sharma", daysAgo: 1)
        let meetingWithSameTitle = recording(.meeting, "Catch-up with Tom Ellis", daysAgo: 2)
        let earlierNote = recording(.voiceNote, "Ideas", daysAgo: 4)
        let note = recording(.voiceNote, "Ideas")
        let all = [current, note, otherPerson, meetingWithSameTitle, renamed, earlierNote, older]

        XCTAssertTrue(MeetingSeries.previous(of: current, in: all) === renamed, "Same person, even after a rename")
        XCTAssertEqual(
            MeetingSeries.all(like: current, in: all).map { ObjectIdentifier($0) },
            [current, renamed, older].map { ObjectIdentifier($0) }
        )
        XCTAssertNil(MeetingSeries.previous(of: note, in: all))
        XCTAssertEqual(MeetingSeries.all(like: note, in: all).count, 1)
        XCTAssertNil(MeetingSeries.previous(of: meetingWithSameTitle, in: all), "A meeting isn't in a catch-up's series")
    }

    func testTodaysDiaryShowsWhatWasRecordedWhatsOnAndWhatWasMissed() {
        func event(_ id: String, _ title: String, at offset: TimeInterval, people: [String] = ["Priya Sharma"]) -> CalendarMeeting {
            CalendarMeeting(id: id, title: title, start: start.addingTimeInterval(offset), end: start.addingTimeInterval(offset + 1_800), attendees: people)
        }
        let huddle = event("A", "Team huddle", at: -1_800)
        let budget = event("B", "Budget review", at: 0)
        let checkIn = event("C", "Weekly check-in", at: 3_600)
        let rota = event("D", "Rota planning", at: 9_000)
        let focus = event("E", "Focus time", at: 5_400, people: [])
        let leave = CalendarMeeting(id: "F", title: "Leave", start: start, end: start.addingTimeInterval(86_400), isAllDay: true, attendees: ["Sam Lee"])
        let recorded = Meeting(title: "Budget review", createdAt: start.addingTimeInterval(60))
        recorded.calendarEventID = "B"

        let entries = DiaryDay.entries(
            events: [rota, checkIn, budget, huddle, focus, leave],
            meetings: [recorded],
            now: start.addingTimeInterval(3_900)
        )

        XCTAssertEqual(entries.map(\.event.id), ["A", "B", "C", "D"], "Blocks with nobody invited and all-day events are left out")
        XCTAssertEqual(entries.map(\.status), [.notRecorded, .recorded, .now, .later])
        XCTAssertTrue(entries[1].meeting === recorded)
    }

    func testAMeetingRecordedBeforeLinksWereKeptStillCountsAsRecorded() {
        let event = CalendarMeeting(id: "B", title: "Budget review", start: start, end: start.addingTimeInterval(1_800), attendees: ["Tom Ellis"])
        XCTAssertTrue(DiaryDay.isRecording(Meeting(title: "Budget review", createdAt: start.addingTimeInterval(-120)), of: event))
        XCTAssertFalse(DiaryDay.isRecording(Meeting(title: "Budget review", createdAt: start.addingTimeInterval(-86_400)), of: event))
        let linkedElsewhere = Meeting(title: "Budget review", createdAt: start)
        linkedElsewhere.calendarEventID = "Z"
        XCTAssertFalse(DiaryDay.isRecording(linkedElsewhere, of: event))
    }

    func testRecentPeopleOffersCatchUpsFirstAndNeverTheUser() {
        let catchUp = recording(.catchUp, "Catch-up with Tom Ellis", with: "Tom Ellis")
        let meeting = recording(.meeting, "Weekly check-in", daysAgo: 1)
        meeting.attendees = ["Sam Lee", "Priya Sharma", "tom ellis"]
        meeting.speakers = [Speaker(id: "S1", number: 1, name: "Priya Sharma"), Speaker(id: "S2", number: 2)]

        XCTAssertEqual(RecentPeople.list(from: [catchUp, meeting], me: "Sam Lee"), ["Tom Ellis", "Priya Sharma"])
    }

    func testAVoiceNotesToDosAreOpenAndUnassigned() throws {
        let context = try makeContext()
        let meeting = Meeting(title: Meeting.defaultTitle(for: start, kind: .voiceNote), createdAt: start, duration: 120)
        meeting.kind = .voiceNote
        context.insert(meeting)
        let insights = MeetingInsights(
            title: "Ideas for the rota handover",
            summary: "- A shared checklist would help.",
            decisions: [],
            actions: [ExtractedAction(task: "Draft a handover checklist", owner: "Tom", due: "By Friday")]
        )

        MeetingProcessor.apply(insights, to: meeting)

        XCTAssertEqual(meeting.title, "Ideas for the rota handover", "The notes title a voice note")
        XCTAssertEqual(meeting.actions.map(\.text), ["Draft a handover checklist"])
        XCTAssertEqual(meeting.actions.first?.status, .open)
        XCTAssertNil(meeting.actions.first?.owner)
    }

    func testTheTypeTravelsInASharedMeeting() throws {
        let context = try makeContext()
        let meeting = recording(.catchUp, "Catch-up with Tom Ellis", with: "Tom Ellis")
        context.insert(meeting)
        let shared = MeetingSharing.document(for: meeting, options: ShareOptions(), sharedBy: "Priya Sharma", recordingBytes: nil)
        XCTAssertEqual(shared.kind, "catchUp")

        let imported = MeetingSharing.importMeeting(shared, recording: nil, replacing: nil, into: context)
        XCTAssertEqual(imported.kind, .catchUp)
        XCTAssertEqual(imported.catchUpPerson, "Tom Ellis")
    }
}
