import Foundation
import SwiftData

/// Runs AI enhancement for a meeting and stores the results.
@MainActor
enum MeetingProcessor {
    static func process(_ meeting: Meeting, using enhancer: NotesEnhancer = NotesEnhancers.best()) async {
        meeting.processingState = .processing
        meeting.processingError = nil
        do {
            let insights = try await enhancer.enhance(segments: meeting.segments, userNotes: meeting.userNotes)
            apply(insights, to: meeting)
            meeting.insightsSource = enhancer.sourceName
            meeting.processingState = .ready
        } catch {
            meeting.processingError = error.localizedDescription
            meeting.processingState = .failed
        }
    }

    static func apply(_ insights: MeetingInsights, to meeting: Meeting) {
        if let title = insights.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           meeting.title == Meeting.defaultTitle(for: meeting.createdAt) {
            meeting.title = title
        }
        meeting.summary = insights.summary
        meeting.decisions = insights.decisions

        // Replace earlier suggestions, but keep anything the user has already reviewed.
        let reviewed = meeting.actions.filter { $0.status != .suggested }
        for stale in meeting.actions where stale.status == .suggested {
            meeting.modelContext?.delete(stale)
        }
        let known = Set(reviewed.map { $0.text.lowercased() })
        let suggestions = insights.actions
            .filter { !known.contains($0.task.lowercased()) }
            .map { extracted in
                ActionItem(
                    text: extracted.task,
                    owner: extracted.owner,
                    due: extracted.due,
                    status: .suggested,
                    sourceSegmentID: meeting.segments.segment(matching: extracted.evidence)?.id
                )
            }
        suggestions.forEach { meeting.modelContext?.insert($0) }
        meeting.actions = reviewed + suggestions
    }
}
