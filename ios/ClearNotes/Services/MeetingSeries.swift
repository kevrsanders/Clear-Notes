import Foundation

/// Finds the previous meeting in a series, for "Last time": the same repeating calendar meeting,
/// or else a meeting with the same title.
enum MeetingSeries {
    /// The most recent meeting in the series from an earlier day than `date`. Earlier days only,
    /// so a recording of today's occurrence never counts as its own "last time".
    @MainActor
    static func previous(
        seriesID: String?,
        title: String,
        kind: MeetingKind = .meeting,
        person: String? = nil,
        before date: Date,
        in meetings: [Meeting],
        calendar: Calendar = .current
    ) -> Meeting? {
        let dayStart = calendar.startOfDay(for: date)
        return meetings
            .filter { $0.createdAt < dayStart && isInSeries($0, kind: kind, seriesID: seriesID, title: title, person: person) }
            .max { $0.createdAt < $1.createdAt }
    }

    /// The previous meeting in the same series as `meeting`, from an earlier day.
    @MainActor
    static func previous(of meeting: Meeting, in meetings: [Meeting]) -> Meeting? {
        previous(
            seriesID: meeting.seriesID,
            title: meeting.title,
            kind: meeting.kind,
            person: meeting.catchUpPerson,
            before: meeting.createdAt,
            in: meetings
        )
    }

    /// Every meeting in the series, newest first, including `meeting` itself.
    @MainActor
    static func all(like meeting: Meeting, in meetings: [Meeting]) -> [Meeting] {
        meetings
            .filter {
                $0 === meeting
                    || isInSeries($0, kind: meeting.kind, seriesID: meeting.seriesID, title: meeting.title, person: meeting.catchUpPerson)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Only recordings of the same type form a series, and voice notes never do. Catch-ups with
    /// the same person belong together. For meetings, calendar IDs are trusted when both have one;
    /// otherwise the title decides.
    @MainActor
    private static func isInSeries(_ meeting: Meeting, kind: MeetingKind, seriesID: String?, title: String, person: String?) -> Bool {
        guard meeting.kind == kind, kind != .voiceNote else { return false }
        if kind == .catchUp, let person, let other = meeting.catchUpPerson {
            return normalizedTitle(person) == normalizedTitle(other)
        }
        if let seriesID, let other = meeting.seriesID { return seriesID == other }
        let key = normalizedTitle(title)
        return !key.isEmpty && normalizedTitle(meeting.title) == key
    }

    /// "Weekly Infra & Cyber catch-up" → "weekly infra cyber catch up"
    static func normalizedTitle(_ title: String) -> String {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
