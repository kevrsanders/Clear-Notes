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
        let key = normalizedTitle(title)
        return meetings
            .filter { $0.createdAt < dayStart }
            .filter { meeting in
                // Calendar IDs are trusted when both meetings have one; otherwise the title decides.
                if let seriesID, let other = meeting.seriesID { return seriesID == other }
                return !key.isEmpty && normalizedTitle(meeting.title) == key
            }
            .max { $0.createdAt < $1.createdAt }
    }

    /// "Weekly Infra & Cyber catch-up" → "weekly infra cyber catch up"
    static func normalizedTitle(_ title: String) -> String {
        title.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .joined(separator: " ")
    }
}
