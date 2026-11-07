import XCTest
@testable import ClearNotes

@MainActor
final class WatchRecordingTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    func testDetailsTravelWithTheFile() {
        let info = WatchRecordingInfo(
            id: UUID(), kind: .catchUp, startedAt: start, duration: 312,
            marks: [40, 95.5], eventID: nil, eventTitle: nil
        )
        XCTAssertEqual(WatchRecordingInfo(metadata: info.metadata), info)
        XCTAssertNil(WatchRecordingInfo(metadata: ["something": "else"]))
        XCTAssertNil(WatchRecordingInfo(metadata: nil))
    }

    func testAVoiceNoteFromTheWatchIsTranscribedFirst() {
        let info = WatchRecordingInfo(id: UUID(), kind: .voiceNote, startedAt: start, duration: 96, marks: [30])
        let meeting = WatchInbox.makeMeeting(from: info, audioFileName: "note.m4a", event: nil)

        XCTAssertEqual(meeting.kind, .voiceNote)
        XCTAssertTrue(meeting.recordedOnWatch)
        XCTAssertTrue(meeting.transcribeFromAudio)
        XCTAssertEqual(meeting.pendingAudioFileName, "note.m4a", "Kept until it's transcribed")
        XCTAssertEqual(meeting.createdAt, start)
        XCTAssertEqual(meeting.duration, 96)
        XCTAssertEqual(meeting.marks.map(\.time), [30])
        XCTAssertTrue(meeting.hasDefaultTitle, "The notes can give it a title")
    }

    func testACatchUpExpectsTwoVoices() {
        let info = WatchRecordingInfo(id: UUID(), kind: .catchUp, startedAt: start, duration: 600)
        let meeting = WatchInbox.makeMeeting(from: info, audioFileName: "chat.m4a", event: nil)
        XCTAssertEqual(meeting.kind, .catchUp)
        XCTAssertEqual(meeting.expectedSpeakers, 2)
    }

    func testARecordingFromAReminderTakesTheDiaryMeeting() {
        let event = CalendarMeeting(
            id: "E1-1", title: "Weekly check-in", start: start, end: start.addingTimeInterval(1_800),
            attendees: ["Priya Sharma", "Tom Ellis"]
        )
        let info = WatchRecordingInfo(id: UUID(), kind: .meeting, startedAt: start, duration: 1_700, eventID: "E1-1", eventTitle: "")
        let meeting = WatchInbox.makeMeeting(from: info, audioFileName: "meeting.m4a", event: event)
        XCTAssertEqual(meeting.title, "Weekly check-in")
        XCTAssertEqual(meeting.calendarEventID, "E1-1")
        XCTAssertTrue(meeting.isFromDiary)

        let unlinked = WatchInbox.makeMeeting(
            from: WatchRecordingInfo(id: UUID(), kind: .meeting, startedAt: start, duration: 60, eventID: "gone", eventTitle: "Budget review"),
            audioFileName: "other.m4a",
            event: nil
        )
        XCTAssertEqual(unlinked.title, "Budget review", "The reminder's title when the event can't be found")
    }
}

@MainActor
final class MeetingReminderTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_793_000_000)

    private func event(_ id: String, _ title: String, in minutes: Double, people: [String] = ["Priya Sharma"]) -> CalendarMeeting {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarMeeting(id: id, title: title, start: start, end: start.addingTimeInterval(1_800), attendees: people)
    }

    func testOnlyUpcomingMeetingsWithPeopleThatWerentRecorded() {
        let past = event("A", "Team huddle", in: -30)
        let recorded = event("B", "Budget review", in: 20)
        let upcoming = event("C", "Weekly check-in", in: 45)
        let block = event("D", "Focus time", in: 60, people: [])
        let meeting = Meeting(title: "Budget review", createdAt: now)
        meeting.calendarEventID = "B"

        let plans = MeetingReminders.plan(events: [upcoming, block, recorded, past, upcoming], meetings: [meeting], now: now, showTitles: false)

        XCTAssertEqual(plans.map(\.eventID), ["C"], "No repeats, nothing past, recorded or without people")
        XCTAssertEqual(plans.first?.fireDate, upcoming.start)
        XCTAssertEqual(plans.first?.identifier, MeetingReminderNotification.identifierPrefix + "C")
    }

    func testTheNameIsLeftOutUnlessChosen() {
        let upcoming = event("C", "Weekly check-in", in: 45, people: ["Priya Sharma", "Tom Ellis"])

        let hidden = MeetingReminders.plan(events: [upcoming], meetings: [], now: now, showTitles: false)
        XCTAssertEqual(hidden.first?.title, "A meeting is starting")
        XCTAssertEqual(hidden.first?.eventTitle, "")
        XCTAssertTrue(hidden.first?.body.hasSuffix("· 2 invited") == true)

        let shown = MeetingReminders.plan(events: [upcoming], meetings: [], now: now, showTitles: true)
        XCTAssertEqual(shown.first?.title, "Weekly check-in is starting")
        XCTAssertEqual(shown.first?.eventTitle, "Weekly check-in")
    }
}

final class PhoneRemoteTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_793_000_000)

    func testTheWatchTimerCountsRecordingTimeOnly() {
        var state = PhoneRecordingState(timerStart: start)
        XCTAssertEqual(state.elapsed(at: start.addingTimeInterval(95)), 95)
        state.pausedAt = start.addingTimeInterval(60)
        XCTAssertEqual(state.elapsed(at: start.addingTimeInterval(500)), 60, "Stops while paused")
        XCTAssertTrue(state.isPaused)
    }

    func testTheRecordingStateTravelsToTheWatch() {
        let state = PhoneRecordingState(timerStart: start, pausedAt: nil, actionMarks: 2, decisionMarks: 1)
        let context = PhoneRecordingState.context(state)
        XCTAssertTrue(PhoneRecordingState.isContext(context))
        XCTAssertEqual(PhoneRecordingState.from(context), state)
        XCTAssertEqual(state.marksText, "2 actions · 1 decision marked")

        let stopped = PhoneRecordingState.context(nil)
        XCTAssertTrue(PhoneRecordingState.isContext(stopped), "Stopping is news too")
        XCTAssertNil(PhoneRecordingState.from(stopped))
        XCTAssertFalse(PhoneRecordingState.isContext(["other": 1]))
    }

    func testWatchCommandsMatchTheLockScreenButtons() {
        for raw in [PhoneRemote.pause, PhoneRemote.resume, PhoneRemote.markAction, PhoneRemote.markDecision] {
            XCTAssertNotNil(RecordingCommand(rawValue: raw), raw)
        }
    }
}
