import SwiftData
import SwiftUI

struct MeetingsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @AppStorage(SettingsKeys.showConsentReminder) private var showConsentReminder = true

    @State private var path: [Meeting] = []
    @State private var search = ""
    @State private var showConsent = false
    @State private var startAfterConsent = false
    @State private var showRecorder = false
    @State private var finishedMeeting: Meeting?

    private var filtered: [Meeting] {
        guard !search.isEmpty else { return meetings }
        return meetings.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.summary.localizedCaseInsensitiveContains(search)
                || $0.userNotes.localizedCaseInsensitiveContains(search)
                || $0.transcriptText.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if meetings.isEmpty {
                    emptyState
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else {
                    list
                }
            }
            .background(Theme.canvas)
            .navigationTitle("Meetings")
            .searchable(text: $search, prompt: "Search notes and transcripts")
            .navigationDestination(for: Meeting.self) { MeetingDetailView(meeting: $0) }
            .safeAreaInset(edge: .bottom) {
                RecordButton(action: newMeeting)
                    .padding(.bottom, 8)
            }
        }
        .sheet(isPresented: $showConsent, onDismiss: {
            if startAfterConsent {
                startAfterConsent = false
                showRecorder = true
            }
        }) {
            ConsentSheet {
                startAfterConsent = true
                showConsent = false
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(isPresented: $showRecorder, onDismiss: openFinishedMeeting) {
            RecordingView(onFinish: saveMeeting)
        }
    }

    private var list: some View {
        List {
            ForEach(filtered) { meeting in
                NavigationLink(value: meeting) {
                    MeetingRow(meeting: meeting)
                }
            }
            .onDelete { offsets in
                offsets.map { filtered[$0] }.forEach { context.delete($0) }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No meetings yet", systemImage: "waveform.badge.mic")
        } description: {
            Text("Tap New meeting to transcribe a conversation on this iPhone. Clear Notes turns it into a summary, decisions and actions. Audio is never saved.")
        }
    }

    private func newMeeting() {
        if showConsentReminder {
            showConsent = true
        } else {
            showRecorder = true
        }
    }

    private func saveMeeting(_ result: RecordingResult, notes: String) {
        let start = Date().addingTimeInterval(-result.duration)
        let meeting = Meeting(
            title: Meeting.defaultTitle(for: start),
            createdAt: start,
            duration: result.duration,
            userNotes: notes,
            segments: result.segments
        )
        context.insert(meeting)
        finishedMeeting = meeting
        Task { await MeetingProcessor.process(meeting) }
    }

    private func openFinishedMeeting() {
        guard let meeting = finishedMeeting else { return }
        finishedMeeting = nil
        path.append(meeting)
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(2)
            Text("\(meeting.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(meeting.duration.durationString)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch meeting.processingState {
            case .processing:
                Label("Writing notes…", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.tint)
            case .failed:
                Label("Notes couldn't be generated", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .ready:
                if !meeting.summary.isEmpty {
                    Text(meeting.summary.replacingOccurrences(of: "- ", with: ""))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            if meeting.openActionCount > 0 {
                Chip(text: "\(meeting.openActionCount) open action\(meeting.openActionCount == 1 ? "" : "s")",
                     systemImage: "checklist", tint: .accentColor)
            }
        }
        .padding(.vertical, 6)
    }
}
