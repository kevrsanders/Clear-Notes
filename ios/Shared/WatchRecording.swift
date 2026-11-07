import Foundation

/// A recording made on Apple Watch, sent to the iPhone with its audio file. The iPhone
/// transcribes it and writes the notes, as for a recording made there.
struct WatchRecordingInfo: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case voiceNote, catchUp, meeting
    }

    var id: UUID
    var kind: Kind
    var startedAt: Date
    var duration: TimeInterval
    /// Moments marked while recording (a to-do in a voice note, an action otherwise), in
    /// seconds from the start.
    var marks: [TimeInterval] = []
    /// The diary meeting it was recorded for, when started from a meeting reminder.
    var eventID: String?
    var eventTitle: String?

    /// The key the recording's details travel under, with the file.
    static let metadataKey = "clearNotesRecording"
}

extension WatchRecordingInfo {
    /// The details as file-transfer metadata (property-list types only).
    var metadata: [String: Any] {
        [Self.metadataKey: (try? JSONEncoder().encode(self)) ?? Data()]
    }

    init?(metadata: [String: Any]?) {
        guard let data = metadata?[Self.metadataKey] as? Data,
              let info = try? JSONDecoder().decode(WatchRecordingInfo.self, from: data)
        else { return nil }
        self = info
    }
}

/// The reminder shown when a meeting in the diary starts. Clear Notes on the iPhone schedules it;
/// on Apple Watch, Record starts a recording on the watch.
enum MeetingReminderNotification {
    static let category = "CLEARNOTES_MEETING_START"
    static let recordAction = "CLEARNOTES_RECORD"
    static let eventIDKey = "eventID"
    static let eventTitleKey = "eventTitle"
    static let identifierPrefix = "clearnotes.meeting-start."
}

/// The iPhone's recording as Apple Watch shows it, so the watch can pause it and mark moments.
/// Sent whenever the recording starts, pauses, resumes, is marked or stops.
struct PhoneRecordingState: Codable, Equatable, Sendable {
    /// When the timer would have started without pauses, so it counts recording time only.
    var timerStart: Date
    /// Set while paused: the timer stops here.
    var pausedAt: Date?
    var actionMarks: Int = 0
    var decisionMarks: Int = 0

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at date: Date) -> TimeInterval {
        max(0, (pausedAt ?? date).timeIntervalSince(timerStart))
    }

    /// "2 actions · 1 decision marked", or nil before anything is marked.
    var marksText: String? {
        var parts: [String] = []
        if actionMarks > 0 { parts.append("\(actionMarks) action\(actionMarks == 1 ? "" : "s")") }
        if decisionMarks > 0 { parts.append("\(decisionMarks) decision\(decisionMarks == 1 ? "" : "s")") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ") + " marked"
    }

    static let contextKey = "phoneRecording"

    /// The state as WatchConnectivity context; empty data means nothing is recording.
    static func context(_ state: PhoneRecordingState?) -> [String: Any] {
        [contextKey: state.flatMap { try? JSONEncoder().encode($0) } ?? Data()]
    }

    /// Whether the context says anything about the iPhone's recording.
    static func isContext(_ context: [String: Any]) -> Bool {
        context[contextKey] != nil
    }

    static func from(_ context: [String: Any]) -> PhoneRecordingState? {
        guard let data = context[contextKey] as? Data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(PhoneRecordingState.self, from: data)
    }
}

/// Commands from the watch to the iPhone's recording. The values match the Lock Screen buttons'.
enum PhoneRemote {
    static let commandKey = "command"
    static let pause = "pause"
    static let resume = "resume"
    static let markAction = "markAction"
    static let markDecision = "markDecision"
}
