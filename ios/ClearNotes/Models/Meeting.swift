import Foundation
import SwiftData

/// One stretch of transcribed speech, with offsets in seconds from the start of the meeting.
struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
}

enum ProcessingState: String, Codable {
    case processing, ready, failed
}

@Model
final class Meeting {
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var userNotes: String
    var summary: String
    var decisions: [String]
    var segments: [TranscriptSegment]
    var processingStateRaw: String
    var processingError: String?
    /// Which engine produced the summary and actions, shown to the user for transparency.
    var insightsSource: String?

    @Relationship(deleteRule: .cascade, inverse: \ActionItem.meeting)
    var actions: [ActionItem] = []

    init(
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        userNotes: String = "",
        segments: [TranscriptSegment] = []
    ) {
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.userNotes = userNotes
        self.summary = ""
        self.decisions = []
        self.segments = segments
        self.processingStateRaw = ProcessingState.processing.rawValue
    }

    var processingState: ProcessingState {
        get { ProcessingState(rawValue: processingStateRaw) ?? .ready }
        set { processingStateRaw = newValue.rawValue }
    }

    var transcriptText: String {
        segments.map(\.text).joined(separator: "\n")
    }

    var openActionCount: Int {
        actions.filter { $0.status == .open || $0.status == .suggested }.count
    }

    static func defaultTitle(for date: Date) -> String {
        "Meeting · " + date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
    }
}
