import Foundation
import SwiftData
import UIKit

/// Runs speaker separation and AI enhancement for a meeting and stores the results.
@MainActor
enum MeetingProcessor {
    private static var inFlight = Set<PersistentIdentifier>()

    static func process(
        _ meeting: Meeting,
        enhancer: NotesEnhancer = NotesEnhancers.best(),
        separator: SpeakerSeparating? = SpeakerSeparators.best()
    ) async {
        guard inFlight.insert(meeting.persistentModelID).inserted else { return }
        defer { inFlight.remove(meeting.persistentModelID) }

        // Ask iOS for time to finish if the user leaves the app straight after recording. On
        // iOS 26 it can carry on for longer, with its progress shown by the system.
        let backgroundTime = BackgroundTime(name: "Process meeting")
        defer { backgroundTime.end() }
        let continued = ContinuedProcessing.shared

        meeting.processingState = .processing
        meeting.processingError = nil
        func stage(_ next: ProcessingStage) {
            meeting.processingStage = next
            continued.update(meeting)
        }
        // The finished recording is protected while the iPhone is locked, so steps that read it
        // wait for it to be unlocked rather than fail. Processing carries on from here then.
        func waitForUnlock() {
            try? meeting.modelContext?.save()
            continued.finish(.waitingForUnlock)
        }

        // A second, more accurate transcription of a new recording, before speakers are found. At
        // most twice, so one that keeps failing or being interrupted isn't redone on every restart.
        let isNew = meeting.pendingAudioFileName != nil || meeting.insightsSource == nil
        let accurateURL: URL? = isNew && !meeting.transcriptImproved && meeting.accuratePassAttempts < 2 && AccurateTranscriber.isReady
            ? meeting.pendingAudioFileName.map({ RecordingStore.url(for: $0) }) ?? meeting.playableAudioURL
            : nil
        // The system's background progress is only for the steps that read the recording: notes
        // need Clear Notes open, so it would only end with an error there.
        if accurateURL != nil || meeting.pendingAudioFileName != nil, AppActivity.isActive {
            continued.begin()
        }

        if let url = accurateURL {
            guard AppActivity.isUnlocked else { return waitForUnlock() }
            stage(.transcript)
            meeting.accuratePassAttempts += 1
            try? meeting.modelContext?.save()
            if await applyAccurateTranscript(to: meeting, from: url) == .locked {
                // Not a real attempt: the iPhone was locked part-way through.
                meeting.accuratePassAttempts -= 1
                return waitForUnlock()
            }
        }

        if let fileName = meeting.pendingAudioFileName {
            guard AppActivity.isUnlocked else { return waitForUnlock() }
            stage(.speakers)
            guard await identifySpeakers(in: meeting, audioFileName: fileName, separator: separator) else {
                return waitForUnlock()
            }
        }

        // The recording steps are done; the notes are written with Clear Notes open.
        continued.finish(.readyForNotes)

        // Names and terms from My words and the people in the meeting, now lines and speakers are settled.
        applyVocabulary(to: meeting)

        meeting.notesPartsDone = 0
        meeting.notesPartsTotal = 0
        stage(.notes)
        let insights: MeetingInsights
        let source: String
        switch await writeNotes(for: meeting, with: enhancer) {
        case .written(let written, let writtenBy):
            insights = written
            source = writtenBy
        case .paused:
            // Apple Intelligence limits apps in the background. The meeting stays in progress, its
            // finished parts are saved, and it carries on when Clear Notes is next opened.
            try? meeting.modelContext?.save()
            continued.finish(.paused)
            return
        case .failed(let message):
            meeting.processingError = message
            meeting.processingState = .failed
            meeting.processingStage = nil
            continued.finish(.failed)
            return
        }
        // Moments marked while recording (taps and spoken phrases) become actions and decisions.
        let marks = meeting.marks + SpokenMarks.find(in: meeting.segments, besides: meeting.marks)
        let marked = await MarkWriter.write(marks, segments: meeting.segments, speakers: meeting.speakers)
        apply(insights, marked: marked, to: meeting)
        meeting.insightsSource = source
        meeting.notesCaveat = insights.note
        meeting.processingState = .ready
        meeting.notesNeedRefresh = false
        meeting.processingStage = nil
        meeting.notesProgressData = nil
        meeting.notesPartsDone = 0
        meeting.notesPartsTotal = 0
        try? meeting.modelContext?.save()
        continued.finish(.done)
    }

    private enum NotesOutcome {
        case written(MeetingInsights, source: String)
        case paused
        case failed(String)
    }

    /// Writes the notes, saving each part as it's finished. When Apple Intelligence is busy with the
    /// app open, it waits and tries again (finished parts aren't redone) before settling for basic
    /// notes; in the background it pauses instead.
    private static func writeNotes(for meeting: Meeting, with enhancer: NotesEnhancer) async -> NotesOutcome {
        let progress = MeetingNotesProgress(meeting: meeting)
        var busyRetries = 0
        while true {
            do {
                let insights = try await enhancer.enhance(
                    segments: meeting.segments,
                    speakers: meeting.speakers,
                    userNotes: meeting.userNotes,
                    progress: progress
                )
                return .written(insights, source: enhancer.sourceName)
            } catch {
                let busy = (error as? NotesEnhancerError) == .busy
                if busy, !AppActivity.isActive {
                    return .paused
                }
                if busy, progress.hasSavedParts, busyRetries < 2 {
                    busyRetries += 1
                    try? await Task.sleep(for: .seconds(30))
                    continue
                }
                // Basic notes are better than none, so fall back when Apple Intelligence can't finish.
                let basic = HeuristicEnhancer()
                guard !(enhancer is HeuristicEnhancer),
                      var fallback = try? await basic.enhance(
                          segments: meeting.segments,
                          speakers: meeting.speakers,
                          userNotes: meeting.userNotes
                      )
                else {
                    return .failed(error.localizedDescription)
                }
                fallback.note = "Apple Intelligence couldn't write these notes because \(NotesEnhancers.reason(for: error)), so basic extraction was used. Try again for fuller notes."
                return .written(fallback, source: basic.sourceName)
            }
        }
    }

    /// Finishes meetings that were still processing when the app was closed, deletes recordings
    /// past their keep-until date, and removes stray audio.
    static func resumeUnfinished(in context: ModelContext) async {
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        for meeting in meetings {
            if let expiry = meeting.audioExpiresAt, expiry < .now {
                meeting.deleteAudio()
            }
        }
        RecordingStore.deleteOrphans(keeping: Set(meetings.flatMap { [$0.pendingAudioFileName, $0.audioFileName] }.compactMap { $0 }))
        await resumeProcessing(in: context)
    }

    /// Carries on with meetings still in progress, e.g. notes paused while the app was in the
    /// background. Safe to call whenever the app becomes active: unlike `resumeUnfinished` it
    /// deletes nothing, so a recording in progress is never touched.
    static func resumeProcessing(in context: ModelContext) async {
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        for meeting in meetings where meeting.processingState == .processing && meeting.deletedAt == nil {
            await process(meeting)
        }
    }

    /// Returns false when the recording couldn't be read because the iPhone was locked. The
    /// recording is then left waiting, and speakers are identified once it's unlocked.
    private static func identifySpeakers(in meeting: Meeting, audioFileName: String, separator: SpeakerSeparating?) async -> Bool {
        // Afterwards the audio is kept for playback or deleted, as the user chose.
        func finish() {
            meeting.pendingAudioFileName = nil
            meeting.keepAudio(audioFileName)
        }
        guard let separator else {
            finish()
            return true
        }
        do {
            let turns = try await separator.separate(
                audioAt: RecordingStore.url(for: audioFileName),
                expectedSpeakers: meeting.expectedSpeakers
            )
            UserDefaults.standard.set(true, forKey: SettingsKeys.speakerModelsReady)
            let assigned = SpeakerAssigner.assign(meeting.segments, turns: turns)
            meeting.segments = assigned.segments
            meeting.speakers = voiceprintsAllowed(assigned.speakers)
            VoiceLibrary.applyMatches(to: meeting)
            meeting.speakerNote = assigned.speakers.isEmpty ? "No separate voices were found." : nil
        } catch {
            if AppActivity.isLockedFileError(error) || !AppActivity.isUnlocked {
                return false
            }
            meeting.speakerNote = "Speakers couldn't be identified. \(error.localizedDescription)"
        }
        finish()
        return true
    }

    /// Runs speaker separation again on the kept recording, for a known number of people.
    /// Speaker names are cleared because the voices are regrouped.
    static func reidentifySpeakers(
        in meeting: Meeting,
        count: Int,
        separator: SpeakerSeparating? = SpeakerSeparators.best()
    ) async {
        guard let separator, let url = meeting.playableAudioURL,
              inFlight.insert(meeting.persistentModelID).inserted
        else { return }
        defer { inFlight.remove(meeting.persistentModelID) }
        let backgroundTime = BackgroundTime(name: "Re-check speakers")
        defer { backgroundTime.end() }

        let previousState = meeting.processingState
        let oldSegments = meeting.segments
        let oldSpeakers = meeting.speakers
        meeting.processingState = .processing
        meeting.processingStage = .speakers
        do {
            let turns = try await separator.separate(audioAt: url, expectedSpeakers: count)
            let unassigned = meeting.segments.map { segment in
                var segment = segment
                segment.speakerID = nil
                return segment
            }
            let assigned = SpeakerAssigner.assign(unassigned, turns: turns)
            meeting.segments = assigned.segments
            // Names stay with the voices that match the old ones, so they needn't be added again.
            let renamed = SpeakerNames.carry(
                from: oldSegments, oldSpeakers: oldSpeakers,
                to: assigned.segments, newSpeakers: assigned.speakers
            )
            meeting.speakers = voiceprintsAllowed(renamed)
            VoiceLibrary.applyMatches(to: meeting)
            meeting.speakerNote = nil
            meeting.expectedSpeakers = count
            meeting.notesNeedRefresh = previousState == .ready
        } catch {
            meeting.speakerNote = "Speakers couldn't be re-checked. \(error.localizedDescription)"
        }
        meeting.processingStage = nil
        meeting.processingState = previousState
    }

    /// Runs the accurate second pass on a meeting's kept recording, e.g. one recorded before it was
    /// turned on. Speaker names are kept, and actions keep their links to where they were said.
    /// Returns false when the recording couldn't be transcribed again.
    @discardableResult
    static func improveTranscript(of meeting: Meeting) async -> Bool {
        guard let url = meeting.playableAudioURL, inFlight.insert(meeting.persistentModelID).inserted else { return false }
        defer { inFlight.remove(meeting.persistentModelID) }
        let backgroundTime = BackgroundTime(name: "Improve transcript")
        defer { backgroundTime.end() }

        let previousState = meeting.processingState
        let oldSegments = meeting.segments
        meeting.processingState = .processing
        meeting.processingStage = .transcript
        let improved = await applyAccurateTranscript(to: meeting, from: url) == .improved
        if improved {
            applyVocabulary(to: meeting)
            for action in meeting.actions {
                guard let id = action.sourceSegmentID, let old = oldSegments.first(where: { $0.id == id }) else { continue }
                action.sourceSegmentID = meeting.segment(at: old.start)?.id
            }
            meeting.notesNeedRefresh = previousState == .ready
            meeting.revision += 1
        }
        meeting.processingStage = nil
        meeting.processingState = previousState
        try? meeting.modelContext?.save()
        return improved
    }

    /// Replaces the transcript with the accurate model's, keeping speakers where they're already
    /// known. Keeps the live transcript if the second pass fails or loses most of the words.
    private enum AccuratePass {
        case improved
        /// The live transcript is kept: the pass failed or lost most of the words.
        case kept
        /// The recording couldn't be read because the iPhone was locked.
        case locked
    }

    @discardableResult
    private static func applyAccurateTranscript(to meeting: Meeting, from url: URL) async -> AccuratePass {
        do {
            let words = try await AccurateTranscriber.shared.words(in: url)
            let original = meeting.segments
            let hasSpeakers = original.contains { $0.speakerID != nil }
            let improved = TranscriptBuilder.segments(from: words) { time in
                hasSpeakers ? TranscriptBuilder.speaker(at: time, in: original) : nil
            }
            guard TranscriptBuilder.isUsable(improved, comparedWith: original) else { return .kept }
            meeting.segments = improved
            meeting.transcriptImproved = true
            return .improved
        } catch {
            return AppActivity.isLockedFileError(error) || !AppActivity.isUnlocked ? .locked : .kept
        }
    }

    /// Corrects names and terms the transcript misheard, from My words and the people in the meeting.
    private static func applyVocabulary(to meeting: Meeting) {
        let fixed = VocabularyFixer.fix(meeting.segments, terms: Vocabulary.terms(for: meeting)) { word in
            MainActor.assumeIsolated { Vocabulary.isRealWord(word) }
        }
        if fixed.map(\.text) != meeting.segments.map(\.text) {
            meeting.segments = fixed
        }
    }

    /// Voiceprints are kept on a meeting only while Remember voices is on.
    private static func voiceprintsAllowed(_ speakers: [Speaker]) -> [Speaker] {
        guard !VoiceLibrary.isEnabled else { return speakers }
        return speakers.map { speaker in
            var speaker = speaker
            speaker.embedding = nil
            return speaker
        }
    }

    static func apply(_ insights: MeetingInsights, marked: MarkedItems = MarkedItems(), to meeting: Meeting) {
        if let title = insights.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !title.isEmpty,
           meeting.title == Meeting.defaultTitle(for: meeting.createdAt) {
            meeting.title = title
        }
        meeting.summary = insights.summary
        // Marked decisions first, then ones the notes found that don't repeat them.
        let found = insights.decisions.filter { decision in
            !marked.decisions.contains { ActionList.similar($0, decision) }
        }
        meeting.decisions = marked.decisions + found
        meeting.topics = insights.topics

        // Replace earlier suggestions, but keep anything the user has already reviewed.
        let reviewed = meeting.actions.filter { $0.status != .suggested }
        for stale in meeting.actions where stale.status == .suggested {
            meeting.modelContext?.delete(stale)
        }
        let known = Set(reviewed.map { $0.text.lowercased() })
        let knownMarks = Set(reviewed.compactMap(\.markID))
        let speakerNames = meeting.speakers.compactMap(\.name)
        let matchOwner: (String?) -> String? = { name in
            name.map { OwnerMatcher.match($0, speakers: speakerNames, attendees: meeting.attendees) }
        }

        // What the user marked is an action already, so it's open rather than waiting for review.
        let markedActions = marked.actions
            .filter { action in action.markID.map { !knownMarks.contains($0) } ?? true }
            .filter { action in !reviewed.contains { ActionList.similar($0.text, action.task) } }
            .map { extracted in
                let item = ActionItem(
                    text: extracted.task,
                    owner: matchOwner(extracted.owner),
                    due: extracted.due,
                    status: .open,
                    sourceSegmentID: sourceSegmentID(forMark: extracted.markID, in: meeting)
                        ?? meeting.segments.segment(matching: extracted.evidence)?.id
                )
                item.markID = extracted.markID
                return item
            }

        let suggestions = ActionPolicy.suggestions(
            from: insights.actions,
            decisions: meeting.decisions,
            marked: marked.actions,
            duration: meeting.duration,
            setting: .current
        )
        .filter { !known.contains($0.task.lowercased()) }
        .map { extracted in
            ActionItem(
                text: extracted.task,
                owner: matchOwner(extracted.owner),
                due: extracted.due,
                status: .suggested,
                sourceSegmentID: meeting.segments.segment(matching: extracted.evidence)?.id
            )
        }
        (markedActions + suggestions).forEach { meeting.modelContext?.insert($0) }
        meeting.actions = reviewed + markedActions + suggestions
    }

    /// The transcript line a mark was made at. A spoken mark takes its line's ID.
    private static func sourceSegmentID(forMark id: UUID?, in meeting: Meeting) -> UUID? {
        guard let id else { return nil }
        if meeting.segments.contains(where: { $0.id == id }) { return id }
        guard let mark = meeting.marks.first(where: { $0.id == id }) else { return nil }
        return meeting.segment(at: mark.time)?.id
    }
}

/// Saves each finished part of a meeting's notes on the meeting, and keeps its progress up to date.
@MainActor
final class MeetingNotesProgress: NotesProgress {
    private let meeting: Meeting
    private var saved: [String: [NotesPart]]

    init(meeting: Meeting) {
        self.meeting = meeting
        saved = NotesCheckpoint.decode(meeting.notesProgressData)
    }

    var hasSavedParts: Bool { !saved.isEmpty }

    func savedParts(for key: String) async -> [NotesPart]? {
        saved[key]
    }

    func save(_ parts: [NotesPart], for key: String) async {
        saved[key] = parts
        meeting.notesProgressData = NotesCheckpoint.encode(saved)
        try? meeting.modelContext?.save()
    }

    func update(done: Int, of total: Int) async {
        meeting.notesPartsDone = done
        meeting.notesPartsTotal = total
        ContinuedProcessing.shared.update(meeting)
    }
}

/// Whether Clear Notes is on screen (Apple Intelligence limits apps in the background), and
/// whether the iPhone is unlocked.
enum AppActivity {
    @MainActor static var isActive: Bool {
        UIApplication.shared.applicationState == .active
    }

    /// The finished recording uses iOS's strongest file protection, so it can only be opened while
    /// the iPhone is unlocked.
    @MainActor static var isUnlocked: Bool {
        UIApplication.shared.isProtectedDataAvailable
    }

    /// A file read refused because the iPhone is locked, e.g. AVFoundation's error -54 ("permission").
    static func isLockedFileError(_ error: Error) -> Bool {
        var current: NSError? = error as NSError
        while let error = current {
            if error.code == -54 { return true }
            if error.domain == NSCocoaErrorDomain, error.code == NSFileReadNoPermissionError { return true }
            if error.domain == NSPOSIXErrorDomain, error.code == Int(EPERM) || error.code == Int(EACCES) { return true }
            current = error.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}

/// Extra time from iOS to finish work after the user leaves the app. It's handed back when the
/// work ends or when iOS says time is up, because holding it past that gets the app terminated.
@MainActor
final class BackgroundTime {
    private var identifier = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
