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
        before date: Date,
        in meetings: [Meeting],
        calendar: Calendar = .current
    ) -> Meeting? {
        let dayStart = calendar.startOfDay(for: date)
        return meetings
            .filter { $0.createdAt < dayStart && isInSeries($0, seriesID: seriesID, title: title) }
            .max { $0.createdAt < $1.createdAt }
    }

    /// Every meeting in the series, newest first, including `meeting` itself.
    @MainActor
    static func all(like meeting: Meeting, in meetings: [Meeting]) -> [Meeting] {
        meetings
            .filter { $0 === meeting || isInSeries($0, seriesID: meeting.seriesID, title: meeting.title) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Calendar IDs are trusted when both meetings have one; otherwise the title decides.
    @MainActor
    private static func isInSeries(_ meeting: Meeting, seriesID: String?, title: String) -> Bool {
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
