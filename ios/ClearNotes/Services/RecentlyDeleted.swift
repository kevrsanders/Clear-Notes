import Foundation
import SwiftData

/// Deleted meetings are kept for a week, recording included, so a mistaken delete can be undone.
/// After that they're deleted for good.
enum RecentlyDeleted {
    static let keepFor: TimeInterval = 7 * 86_400

    /// Shown when deleting a meeting, which offers both.
    static let choiceMessage = "Recently deleted keeps it for 7 days, recording included, so you can restore it. Delete permanently removes it from this iPhone now and can't be undone."

    /// When a meeting deleted at `deletedAt` is deleted for good.
    static func expiry(of deletedAt: Date) -> Date {
        deletedAt.addingTimeInterval(keepFor)
    }

    static func isExpired(_ deletedAt: Date, now: Date = .now) -> Bool {
        now >= expiry(of: deletedAt)
    }

    /// Calendar days until it's deleted for good: 7 on the day it's deleted, 0 on its last day.
    static func daysLeft(_ deletedAt: Date, now: Date = .now, calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: now),
            to: calendar.startOfDay(for: expiry(of: deletedAt))
        ).day ?? 0
        return max(days, 0)
    }

    /// "Deleted today · 7 days left"
    static func statusLine(_ deletedAt: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let when = calendar.isDate(deletedAt, inSameDayAs: now)
            ? "Deleted today"
            : "Deleted " + deletedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let left = daysLeft(deletedAt, now: now, calendar: calendar)
        let remaining = switch left {
        case 0: "deleted for good today"
        case 1: "1 day left"
        default: "\(left) days left"
        }
        return "\(when) · \(remaining)"
    }

    /// Deletes a meeting and its recording from the iPhone, with no way back.
    @MainActor
    static func deleteForGood(_ meeting: Meeting, in context: ModelContext) {
        meeting.deleteAllAudio()
        context.delete(meeting)
        try? context.save()
    }

    /// Deletes for good every meeting that has been in Recently deleted for a week.
    @MainActor
    static func purgeExpired(in context: ModelContext, now: Date = .now) {
        let descriptor = FetchDescriptor<Meeting>(predicate: #Predicate { $0.deletedAt != nil })
        var purged = false
        for meeting in (try? context.fetch(descriptor)) ?? [] {
            guard let deletedAt = meeting.deletedAt, isExpired(deletedAt, now: now) else { continue }
            meeting.deleteAllAudio()
            context.delete(meeting)
            purged = true
        }
        if purged { try? context.save() }
    }
}
