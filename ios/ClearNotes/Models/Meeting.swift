import Foundation
import SwiftData

/// A recognised word with its offset in seconds from the start of the meeting.
struct TimedWord: Codable, Hashable, Sendable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
}

/// One stretch of transcribed speech, with offsets in seconds from the start of the meeting.
struct TranscriptSegment: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String
    var speakerID: String?
    /// Word timings, kept only until speakers have been identified.
    var words: [TimedWord]?
}

/// A voice found by speaker separation. Unnamed speakers show as "Speaker 2" until the user names them.
struct Speaker: Codable, Hashable, Identifiable, Sendable {
    var id: String
    /// 1-based, in order of first appearance. Also picks the speaker's colour.
    var number: Int
    var name: String?

    var displayName: String { name ?? "Speaker \(number)" }
}

enum ProcessingState: String, Codable {
    case processing, ready, failed
}

enum ProcessingStage: String, Codable {
    case speakers, notes
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
    var speakers: [Speaker] = []
    var processingStateRaw: String
    var processingStageRaw: String?
    var processingError: String?
    /// Why speakers couldn't be identified, shown on the meeting.
    var speakerNote: String?
    /// Which engine produced the summary and actions, shown to the user for transparency.
    var insightsSource: String?
    /// Temporary audio kept only until speakers are identified, then deleted.
    var pendingAudioFileName: String?
    /// Set when speakers are renamed after notes were written, so the user can refresh them.
    var notesNeedRefresh: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \ActionItem.meeting)
    var actions: [ActionItem] = []

    init(
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval = 0,
        userNotes: String = "",
        segments: [TranscriptSegment] = [],
        pendingAudioFileName: String? = nil
    ) {
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.userNotes = userNotes
        self.summary = ""
        self.decisions = []
        self.segments = segments
        self.processingStateRaw = ProcessingState.processing.rawValue
        self.pendingAudioFileName = pendingAudioFileName
    }

    var processingState: ProcessingState {
        get { ProcessingState(rawValue: processingStateRaw) ?? .ready }
        set { processingStateRaw = newValue.rawValue }
    }

    var processingStage: ProcessingStage? {
        get { processingStageRaw.flatMap(ProcessingStage.init(rawValue:)) }
        set { processingStageRaw = newValue?.rawValue }
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

    // MARK: - Speakers

    func speaker(withID id: String?) -> Speaker? {
        guard let id else { return nil }
        return speakers.first { $0.id == id }
    }

    /// Names of speakers the user has named, keyed by speaker ID.
    var speakerNames: [String: String] {
        Dictionary(uniqueKeysWithValues: speakers.compactMap { speaker in
            speaker.name.map { (speaker.id, $0) }
        })
    }

    var hasUnnamedSpeakers: Bool {
        speakers.contains { $0.name == nil }
    }

    /// Names one speaker everywhere in the meeting.
    func renameSpeaker(_ id: String, to name: String?) {
        var updated = speakers
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updated[index].name = trimmed.isEmpty ? nil : trimmed
        speakers = updated
        notesNeedRefresh = processingState == .ready
    }

    /// Treats two voices as the same person, e.g. when separation split one person in two.
    func mergeSpeaker(_ id: String, into targetID: String) {
        guard id != targetID, speaker(withID: targetID) != nil else { return }
        segments = segments.map { segment in
            var segment = segment
            if segment.speakerID == id { segment.speakerID = targetID }
            return segment
        }
        speakers = speakers.filter { $0.id != id }
        notesNeedRefresh = processingState == .ready
    }

    /// Moves one line of the transcript to a different speaker.
    func reassignSegment(_ segmentID: UUID, to speakerID: String) {
        segments = segments.map { segment in
            var segment = segment
            if segment.id == segmentID { segment.speakerID = speakerID }
            return segment
        }
        notesNeedRefresh = processingState == .ready
    }
}
