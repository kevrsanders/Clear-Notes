import Foundation

/// How an event in today's diary stands.
enum DiaryStatus: Equatable {
    /// There's a recording for it.
    case recorded
    /// On now, or starting within a few minutes.
    case now
    case later
    /// Over, with nothing recorded.
    case notRecorded
}

struct DiaryEntry: Identifiable {
    var event: CalendarMeeting
    var status: DiaryStatus
    /// The recording made for it, when there is one.
    var meeting: Meeting?
    var id: String { event.id }
}

/// Today's diary at a glance: which meetings were recorded, which is on now, and what's later.
enum DiaryDay {
    /// Events starting this soon count as on now, matching what Record offers.
    static let lookahead: TimeInterval = 10 * 60

    /// Today's meetings with other people (and any event that was recorded), in time order. All-day
    /// events, cancelled or declined ones and long blocks such as "Working from home" are left out.
    @MainActor
    static func entries(events: [CalendarMeeting], meetings: [Meeting], now: Date) -> [DiaryEntry] {
        events
            .filter(CalendarMeetingPicker.usable)
            .sorted { $0.start < $1.start }
            .compactMap { event in
                let recording = meetings.first { isRecording($0, of: event) }
                guard event.hasPeople || recording != nil else { return nil }
                let status: DiaryStatus
                if recording != nil {
                    status = .recorded
                } else if event.end <= now {
                    status = .notRecorded
                } else if event.start <= now.addingTimeInterval(lookahead) {
                    status = .now
                } else {
                    status = .later
                }
                return DiaryEntry(event: event, status: status, meeting: recording)
            }
    }

    /// A recording made for the event: one linked to it, or (recorded before links were kept) a
    /// meeting with its title that started during it.
    @MainActor
    static func isRecording(_ meeting: Meeting, of event: CalendarMeeting) -> Bool {
        if let id = meeting.calendarEventID { return id == event.id }
        guard meeting.kind == .meeting, !event.title.isEmpty else { return false }
        return meeting.title == event.title
            && meeting.createdAt >= event.start.addingTimeInterval(-15 * 60)
            && meeting.createdAt < event.end
    }
}

/// People to offer when the user says who a catch-up is with.
enum RecentPeople {
    /// Who recent catch-ups were with first, then people named or invited in recent meetings.
    /// Never the user, and no one twice. `meetings` are newest first.
    @MainActor
    static func list(from meetings: [Meeting], me: String, limit: Int = 8) -> [String] {
        let me = me.trimmingCharacters(in: .whitespaces).lowercased()
        let catchUps = meetings.compactMap(\.catchUpPerson)
        let others = meetings.prefix(30).flatMap { meeting in
            meeting.speakers.sorted { $0.number < $1.number }.compactMap(\.name) + meeting.attendees
        }
        var seen: Set<String> = me.isEmpty ? [] : [me]
        var result: [String] = []
        for name in catchUps + others {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            result.append(trimmed)
            if result.count == limit { break }
        }
        return result
    }
}

/// The filter above the list of meetings on the home screen.
enum MeetingFilter: String, CaseIterable, Identifiable {
    case all, diary, catchUps, voiceNotes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .diary: "Diary"
        case .catchUps: "Catch-ups"
        case .voiceNotes: "Voice notes"
        }
    }

    @MainActor
    func matches(_ meeting: Meeting) -> Bool {
        switch self {
        case .all: true
        case .diary: meeting.isFromDiary
        case .catchUps: meeting.kind == .catchUp
        case .voiceNotes: meeting.kind == .voiceNote
        }
    }
}
