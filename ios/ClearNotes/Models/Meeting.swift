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
    /// Voiceprint for this meeting, kept only while Remember voices is on.
    var embedding: [Float]?
    /// A remembered voice this sounds like, waiting for the user to confirm.
    var suggestedName: String?
    var suggestedProfileID: String?
    /// The remembered voice this speaker was matched to.
    var matchedProfileID: String?

    var displayName: String { name ?? "Speaker \(number)" }
}

/// A moment marked while recording: a tap on Mark action or Mark decision just after one was
/// agreed, or a spoken phrase such as "action point". Times match the transcript's.
struct MeetingMark: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case action, decision
    }

    enum Source: String, Codable, Sendable {
        case tap, spoken
    }

    var id = UUID()
    var kind: Kind
    var time: TimeInterval
    var source: Source = .tap
}

/// A stretch of the meeting about one subject, e.g. "Launch timing" from 6:40 to 14:05.
struct Topic: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var start: TimeInterval
    var end: TimeInterval
    var points: [String] = []
}

enum ProcessingState: String, Codable {
    case processing, ready, failed
}

enum ProcessingStage: String, Codable {
    case transcript, speakers, notes
}

@Model
final class Meeting {
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var userNotes: String
    var summary: String
    var decisions: [String]
    var topics: [Topic] = []
    var segments: [TranscriptSegment]
    var speakers: [Speaker] = []
    var processingStateRaw: String
    var processingStageRaw: String?
    var processingError: String?
    /// Why speakers couldn't be identified, shown on the meeting.
    var speakerNote: String?
    /// Which engine produced the summary and actions, shown to the user for transparency.
    var insightsSource: String?
    /// Why the notes are basic or partly basic (e.g. Apple Intelligence declined part), when they are.
    var notesCaveat: String?
    /// Audio waiting for speaker separation.
    var pendingAudioFileName: String?
    /// Audio kept for playback, deleted at `audioExpiresAt` (never, if nil) or by the user.
    var audioFileName: String?
    var audioExpiresAt: Date?
    /// Set when speakers are renamed after notes were written, so the user can refresh them.
    var notesNeedRefresh: Bool = false
    /// Bumped on every speaker edit. Views read it so changes inside `segments` always redraw.
    var revision: Int = 0
    /// Names of people invited, from the calendar event the recording was linked to.
    var attendees: [String] = []
    /// Moments the user marked as actions or decisions while recording.
    var marks: [MeetingMark] = []
    /// The repeating calendar meeting this recording belongs to, for showing "Last time".
    var seriesID: String?
    /// The transcript came from the more accurate second pass, so it isn't redone automatically.
    var transcriptImproved: Bool = false
    /// The Teams join link from the invite, kept for importing the Teams transcript later.
    var teamsJoinURL: String?
    /// How many people spoke, when the user said so (on the recording screen or with "Wrong number
    /// of speakers?"). Nil means the number of voices is worked out from the recording.
    var expectedSpeakers: Int?
    /// Formal minutes (the Minutes tab), written when the user asks, as plain text they can edit.
    var minutes: String = ""
    /// How the minutes were written, e.g. by Apple Intelligence on this iPhone.
    var minutesSource: String?
    var minutesWrittenAt: Date?
    /// Minutes are being written, or paused part-way while Clear Notes was in the background.
    var minutesInProgress: Bool = false
    /// Minutes items written so far (see `MinutesCheckpoint`), until the minutes are finished.
    var minutesProgressData: Data?
    /// Parts of the notes already written (see `NotesCheckpoint`), so a long meeting's notes carry
    /// on where they stopped if iOS pauses Clear Notes. Cleared when the notes are finished.
    var notesProgressData: Data?
    /// How many parts of the notes are written, for "Part 12 of 38".
    var notesPartsDone: Int = 0
    var notesPartsTotal: Int = 0
    /// Times the more accurate second pass has been started, so a pass that keeps failing or
    /// being interrupted isn't repeated on every restart.
    var accuratePassAttempts: Int = 0
    /// The same for every copy of a shared meeting, so importing it again can update a copy.
    var shareID: UUID?
    /// Who shared this meeting, when it was imported from a Clear Notes file.
    var sharedBy: String?
    var importedAt: Date?
    /// When the user deleted it. It stays in Recently deleted for `RecentlyDeleted.keepFor`,
    /// recording included, and is then deleted for good. Nil for meetings in use.
    var deletedAt: Date?

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

    // MARK: - Recently deleted

    /// Moves the meeting to Recently deleted, where it can be restored for a week.
    func moveToRecentlyDeleted(at date: Date = .now) {
        deletedAt = date
        try? modelContext?.save()
    }

    func restoreFromRecentlyDeleted() {
        deletedAt = nil
        try? modelContext?.save()
    }

    // MARK: - Calendar

    /// Takes the title, invited people and Teams link from the calendar event this recording was made in.
    func link(to event: CalendarMeeting) {
        if !event.title.isEmpty { title = event.title }
        // The person recording was at the meeting, as organiser or attendee, so they're listed
        // first: by the calendar's name for them, or else their name from Settings.
        let settingsName = UserDefaults.standard.string(forKey: SettingsKeys.myName)
        attendees = Self.people(event.attendees, me: event.myName ?? settingsName)
        teamsJoinURL = event.teamsJoinURL?.absoluteString
        seriesID = event.seriesID
    }

    /// The user first (when their name is known and not already listed), then everyone else.
    static func people(_ others: [String], me: String?) -> [String] {
        guard let me = me?.trimmingCharacters(in: .whitespaces), !me.isEmpty,
              !others.contains(where: { $0.caseInsensitiveCompare(me) == .orderedSame })
        else { return others }
        return [me] + others
    }

    // MARK: - Recording

    /// The kept recording, if it is still on the iPhone.
    var playableAudioURL: URL? {
        guard let audioFileName else { return nil }
        let url = RecordingStore.url(for: audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Keeps a finished recording for playback, or deletes it, depending on the user's setting.
    func keepAudio(_ fileName: String?, retention: AudioRetention = .current) {
        guard let fileName else { return }
        if retention.keepsAudio {
            audioFileName = fileName
            audioExpiresAt = retention.expiry(from: createdAt)
        } else {
            RecordingStore.delete(fileName)
        }
    }

    func deleteAudio() {
        RecordingStore.delete(audioFileName)
        audioFileName = nil
        audioExpiresAt = nil
    }

    /// Removes every audio file belonging to this meeting, e.g. before deleting it.
    func deleteAllAudio() {
        RecordingStore.delete(pendingAudioFileName)
        pendingAudioFileName = nil
        deleteAudio()
    }

    // MARK: - Speakers

    /// Seconds each speaker talked for, keyed by speaker ID.
    var talkTime: [String: TimeInterval] {
        TalkTime.bySpeaker(segments)
    }

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

    /// Saves a speaker edit straight away and marks the notes as out of date.
    private func didEditSpeakers() {
        revision += 1
        notesNeedRefresh = processingState == .ready
        try? modelContext?.save()
    }

    /// Names one speaker everywhere in the meeting.
    func renameSpeaker(_ id: String, to name: String?) {
        var updated = speakers
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updated[index].name = trimmed.isEmpty ? nil : trimmed
        speakers = updated
        didEditSpeakers()
    }

    /// Changes one speaker in place.
    private func updateSpeaker(_ id: String, _ change: (inout Speaker) -> Void) {
        var updated = speakers
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        change(&updated[index])
        speakers = updated
    }

    /// Accepts a "sounds like" suggestion: names the speaker and links the remembered voice.
    func confirmSuggestion(for id: String) {
        updateSpeaker(id) { speaker in
            guard let suggested = speaker.suggestedName else { return }
            speaker.name = suggested
            speaker.matchedProfileID = speaker.suggestedProfileID
            speaker.suggestedName = nil
            speaker.suggestedProfileID = nil
        }
        didEditSpeakers()
    }

    func rejectSuggestion(for id: String) {
        updateSpeaker(id) { speaker in
            speaker.suggestedName = nil
            speaker.suggestedProfileID = nil
        }
        didEditSpeakers()
    }

    /// Removes voiceprints and voice links, e.g. when the user deletes remembered voices.
    func forgetVoiceprints() {
        speakers = speakers.map { speaker in
            var speaker = speaker
            speaker.embedding = nil
            speaker.suggestedName = nil
            speaker.suggestedProfileID = nil
            speaker.matchedProfileID = nil
            return speaker
        }
    }

    /// Adds an unnamed speaker, for splitting out a voice that separation missed.
    @discardableResult
    func addSpeaker() -> Speaker {
        let number = (speakers.map(\.number).max() ?? 0) + 1
        let speaker = Speaker(id: "S\(number)", number: number)
        speakers = speakers + [speaker]
        didEditSpeakers()
        return speaker
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
        didEditSpeakers()
    }

    // MARK: - Decisions and actions

    /// Turns an action into a decision, for one that was really something agreed.
    func makeDecision(from action: ActionItem) {
        decisions = decisions + [action.text]
        actions.removeAll { $0.persistentModelID == action.persistentModelID }
        modelContext?.delete(action)
        try? modelContext?.save()
    }

    /// Turns a decision into an open action, for one that was really a task.
    func makeAction(fromDecisionAt index: Int) {
        guard decisions.indices.contains(index) else { return }
        let action = ActionItem(text: decisions[index], status: .open)
        modelContext?.insert(action)
        actions.append(action)
        var remaining = decisions
        remaining.remove(at: index)
        decisions = remaining
        try? modelContext?.save()
    }

    /// The transcript line being spoken at a moment, e.g. where a mark was made.
    func segment(at time: TimeInterval) -> TranscriptSegment? {
        segments.last { $0.start <= time } ?? segments.first
    }

    /// Corrects the words of one transcript line.
    func editSegmentText(_ segmentID: UUID, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        segments = segments.map { segment in
            var segment = segment
            if segment.id == segmentID {
                segment.text = trimmed
                // Word timings no longer match the edited words.
                segment.words = nil
            }
            return segment
        }
        didEditSpeakers()
    }

    /// Moves one line of the transcript to a different speaker.
    func reassignSegment(_ segmentID: UUID, to speakerID: String) {
        reassignSegments([segmentID], to: speakerID)
    }

    /// Accepts (as open actions) or dismisses every suggested action at once.
    func reviewAllSuggestions(accept: Bool) {
        for action in actions where action.status == .suggested {
            action.status = accept ? .open : .dismissed
        }
        try? modelContext?.save()
    }

    /// Moves several lines to one speaker at once, e.g. a stretch where two voices were confused.
    func reassignSegments(_ segmentIDs: Set<UUID>, to speakerID: String) {
        guard !segmentIDs.isEmpty else { return }
        segments = segments.map { segment in
            var segment = segment
            if segmentIDs.contains(segment.id) { segment.speakerID = speakerID }
            return segment
        }
        didEditSpeakers()
    }
}

enum TalkTime {
    /// Seconds each speaker talked for, keyed by speaker ID. Lines without a speaker are ignored.
    static func bySpeaker(_ segments: [TranscriptSegment]) -> [String: TimeInterval] {
        segments.reduce(into: [:]) { totals, segment in
            guard let id = segment.speakerID else { return }
            totals[id, default: 0] += max(0, segment.end - segment.start)
        }
    }

    /// Each speaker's share of the total, from 0 to 1.
    static func shares(_ totals: [String: TimeInterval]) -> [String: Double] {
        let total = totals.values.reduce(0, +)
        guard total > 0 else { return [:] }
        return totals.mapValues { $0 / total }
    }
}
