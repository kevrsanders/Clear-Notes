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
