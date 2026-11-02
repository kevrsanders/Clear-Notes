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

        // Ask iOS for time to finish if the user leaves the app straight after recording.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Process meeting")
        defer { UIApplication.shared.endBackgroundTask(backgroundTask) }

        meeting.processingState = .processing
        meeting.processingError = nil

        if let fileName = meeting.pendingAudioFileName {
            meeting.processingStage = .speakers
            await identifySpeakers(in: meeting, audioFileName: fileName, separator: separator)
        }

        meeting.processingStage = .notes
        do {
            let insights = try await enhancer.enhance(
                segments: meeting.segments,
                speakers: meeting.speakers,
                userNotes: meeting.userNotes
            )
            apply(insights, to: meeting)
            meeting.insightsSource = enhancer.sourceName
            meeting.processingState = .ready
            meeting.notesNeedRefresh = false
        } catch {
            meeting.processingError = error.localizedDescription
            meeting.processingState = .failed
        }
        meeting.processingStage = nil
    }

    /// Finishes meetings that were still processing when the app was closed, and removes stray audio.
    static func resumeUnfinished(in context: ModelContext) async {
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        RecordingStore.deleteOrphans(keeping: Set(meetings.compactMap(\.pendingAudioFileName)))
        for meeting in meetings where meeting.processingState == .processing {
            await process(meeting)
        }
    }

    private static func identifySpeakers(in meeting: Meeting, audioFileName: String, separator: SpeakerSeparating?) async {
        // The audio is deleted whatever happens: it exists only for this step.
        defer {
            RecordingStore.delete(audioFileName)
            meeting.pendingAudioFileName = nil
        }
        guard let separator else { return }
        do {
            let turns = try await separator.separate(audioAt: RecordingStore.url(for: audioFileName))
            UserDefaults.standard.set(true, forKey: SettingsKeys.speakerModelsReady)
            let assigned = SpeakerAssigner.assign(meeting.segments, turns: turns)
            meeting.segments = assigned.segments
            meeting.speakers = assigned.speakers
            meeting.speakerNote = assigned.speakers.isEmpty ? "No separate voices were found." : nil
        } catch {
            meeting.speakerNote = "Speakers couldn't be identified. \(error.localizedDescription)"
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
        meeting.topics = insights.topics

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
