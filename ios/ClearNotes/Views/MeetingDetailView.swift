import SwiftData
import SwiftUI
import UIKit

struct MeetingDetailView: View {
    enum Pane: Hashable {
        case overview, actions, transcript, notes
    }

    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pane: Pane = .overview
    @State private var highlightedSegment: UUID?
    @State private var namingSpeaker: Speaker?
    @State private var newActionText = ""
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var confirmDelete = false

    private var toReview: [ActionItem] { sortedActions.filter { $0.status == .suggested } }
    private var open: [ActionItem] { sortedActions.filter { $0.status == .open } }
    private var done: [ActionItem] { sortedActions.filter { $0.status == .done } }
    private var sortedActions: [ActionItem] { meeting.actions.sorted { $0.createdAt < $1.createdAt } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if meeting.processingState == .processing {
                        ProcessingCard(meeting: meeting)
                    } else {
                        speakersSection
                        PillTabs<Pane>(
                            items: [
                                .init(value: .overview, title: "Overview"),
                                .init(value: .actions, title: "Actions", badge: toReview.count),
                                .init(value: .transcript, title: "Transcript"),
                                .init(value: .notes, title: "Notes"),
                            ],
                            selection: $pane
                        )
                        switch pane {
                        case .overview: overviewPane
                        case .actions: actionsPane
                        case .transcript: transcriptPane
                        case .notes: notesPane
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 40)
            }
            .onChange(of: highlightedSegment) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background { GlowBackground() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $namingSpeaker) { speaker in
            SpeakerNamingSheet(meeting: meeting, speaker: speaker)
                .presentationDetents([.fraction(0.75), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
        }
        .alert("Rename meeting", isPresented: $isRenaming) {
            TextField("Title", text: $draftTitle)
            Button("Save") {
                let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { meeting.title = title }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete this meeting?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                RecordingStore.delete(meeting.pendingAudioFileName)
                context.delete(meeting)
                dismiss()
            }
        } message: {
            Text("The transcript, notes and actions will be deleted from this iPhone.")
        }
    }

    // MARK: - Header and toolbar

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(meeting.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
            Text(meeting.title)
                .font(.system(size: 28, weight: .bold))
                .tracking(-0.4)
                .fixedSize(horizontal: false, vertical: true)
            FlowLayout(spacing: 6) {
                Chip(text: meeting.duration.durationString, systemImage: "clock")
                if !meeting.speakers.isEmpty {
                    Chip(text: "\(meeting.speakers.count) speaker\(meeting.speakers.count == 1 ? "" : "s")", systemImage: "person.2.fill")
                }
                Chip(text: "On-device", systemImage: "lock.fill", tint: Theme.brand)
            }
        }
        .padding(.top, 4)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            ShareLink(item: MarkdownExporter.markdown(for: meeting)) {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share notes")
            Menu {
                Button {
                    UIPasteboard.general.string = MarkdownExporter.markdown(for: meeting)
                } label: {
                    Label("Copy as text", systemImage: "doc.on.doc")
                }
                Button {
                    draftTitle = meeting.title
                    isRenaming = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                Button {
                    Task { await MeetingProcessor.process(meeting) }
                } label: {
                    Label("Regenerate notes", systemImage: "sparkles")
                }
                .disabled(meeting.processingState == .processing)
                Divider()
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("More")
        }
    }

    // MARK: - Speakers

    @ViewBuilder
    private var speakersSection: some View {
        if !meeting.speakers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Eyebrow("Speakers")
                    Spacer()
                    Text("Tap to rename")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(meeting.speakers) { speaker in
                            Button {
                                namingSpeaker = speaker
                            } label: {
                                VStack(spacing: 6) {
                                    Avatar(speaker: speaker, size: 44)
                                    Text(speaker.displayName)
                                        .font(.caption.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if speaker.name == nil {
                                        Text("Tap to name")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Theme.brand)
                                    }
                                }
                                .frame(minWidth: 56)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(speaker.name == nil ? "Name \(speaker.displayName)" : "Rename \(speaker.displayName)")
                        }
                    }
                }
            }
            .cardStyle(padding: 16)
        } else if let note = meeting.speakerNote {
            Label(note, systemImage: "person.2.slash")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }

        if meeting.notesNeedRefresh {
            HStack(spacing: 12) {
                Text("Speaker names changed. Refresh the notes to use them.")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Button("Refresh") {
                    Task { await MeetingProcessor.process(meeting) }
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))
            }
            .padding(14)
            .background(Theme.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        } else if let unnamed = meeting.speakers.first(where: { $0.name == nil }) {
            Button {
                namingSpeaker = unnamed
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Name \(unnamed.displayName) to improve notes")
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.brand)
                .padding(14)
                .background(Theme.brand.opacity(0.10), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Overview

    private var overviewPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            if meeting.processingState == .failed {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "Notes couldn't be generated", systemImage: "exclamationmark.triangle.fill", tint: Theme.warning)
                    Text(meeting.processingError ?? "Something went wrong.")
                        .foregroundStyle(Theme.textSecondary)
                    Button("Try again") {
                        Task { await MeetingProcessor.process(meeting) }
                    }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
                }
                .cardStyle()
            }

            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Summary", systemImage: "sparkles")
                BulletList(text: meeting.summary.isEmpty ? "No summary yet." : meeting.summary)
            }
            .cardStyle()

            if !meeting.decisions.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    CardHeader(title: "Decisions", systemImage: "signpost.right.fill", tint: Theme.success)
                    ForEach(Array(meeting.decisions.enumerated()), id: \.offset) { index, decision in
                        HStack(alignment: .top, spacing: 12) {
                            Text("\(index + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Theme.success, in: Circle())
                            Text(decision)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .cardStyle()
            }

            if !toReview.isEmpty {
                Button {
                    withAnimation(.snappy) { pane = .actions }
                } label: {
                    HStack(spacing: 12) {
                        IconTile(systemName: "checklist", tint: nil, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(toReview.count) action\(toReview.count == 1 ? "" : "s") to review")
                                .font(.headline)
                                .foregroundStyle(.primary)
                            Text("Accept the ones that are right")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .cardStyle(padding: 16)
                }
                .buttonStyle(.plain)
            }

            if let source = meeting.insightsSource {
                Label("Written by \(source). Check before sharing.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Actions

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if toReview.isEmpty && open.isEmpty && done.isEmpty {
                Text("No actions yet. Add one below.")
                    .foregroundStyle(Theme.textSecondary)
                    .cardStyle()
            }
            actionGroup("To review", toReview)
            actionGroup("Open", open)
            actionGroup("Done", done)

            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.brand)
                TextField("Add an action", text: $newActionText)
                    .submitLabel(.done)
                    .onSubmit(addAction)
                if !newActionText.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: addAction)
                        .buttonStyle(PrimaryButtonStyle(compact: true))
                }
            }
            .cardStyle(padding: 16)
        }
    }

    @ViewBuilder
    private func actionGroup(_ title: String, _ items: [ActionItem]) -> some View {
        if !items.isEmpty {
            Eyebrow(title)
                .padding(.top, 6)
            ForEach(items) { action in
                ActionCard(action: action, onShowSource: sourceHandler(for: action))
            }
        }
    }

    /// Jumps to the transcript line an action came from, if it has one.
    private func sourceHandler(for action: ActionItem) -> (() -> Void)? {
        guard let id = action.sourceSegmentID else { return nil }
        return {
            withAnimation(.snappy) { pane = .transcript }
            highlightedSegment = id
        }
    }

    private func addAction() {
        let text = newActionText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let action = ActionItem(text: text, status: .open)
        context.insert(action)
        meeting.actions.append(action)
        newActionText = ""
    }

    // MARK: - Transcript

    private struct Turn: Identifiable {
        var speakerID: String?
        var segments: [TranscriptSegment]
        var id: UUID { segments[0].id }
    }

    /// Consecutive lines from the same speaker, shown as one block.
    private var turns: [Turn] {
        var turns: [Turn] = []
        for segment in meeting.segments {
            if let last = turns.last, last.speakerID == segment.speakerID {
                turns[turns.count - 1].segments.append(segment)
            } else {
                turns.append(Turn(speakerID: segment.speakerID, segments: [segment]))
            }
        }
        return turns
    }

    /// How many actions point at each transcript line.
    private var sourceCounts: [UUID: Int] {
        meeting.actions.reduce(into: [:]) { counts, action in
            if let id = action.sourceSegmentID, action.status != .dismissed { counts[id, default: 0] += 1 }
        }
    }

    private var transcriptPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            if meeting.segments.isEmpty {
                Text("Nothing was transcribed.")
                    .foregroundStyle(Theme.textSecondary)
                    .cardStyle()
            }
            let counts = sourceCounts
            ForEach(turns) { turn in
                TurnView(
                    turn: turn,
                    speaker: meeting.speaker(withID: turn.speakerID),
                    showsAvatars: !meeting.speakers.isEmpty,
                    allSpeakers: meeting.speakers,
                    highlightedSegment: highlightedSegment,
                    sourceCounts: counts,
                    onName: { namingSpeaker = $0 },
                    onReassign: { segmentID, speakerID in meeting.reassignSegment(segmentID, to: speakerID) }
                )
            }
        }
        .padding(.top, 4)
    }

    private struct TurnView: View {
        var turn: Turn
        var speaker: Speaker?
        var showsAvatars: Bool
        var allSpeakers: [Speaker]
        var highlightedSegment: UUID?
        var sourceCounts: [UUID: Int]
        var onName: (Speaker) -> Void
        var onReassign: (UUID, String) -> Void

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                if let speaker {
                    Avatar(speaker: speaker, size: 32)
                } else if showsAvatars {
                    Avatar(name: nil, color: Theme.textTertiary, size: 32)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let speaker {
                            Button {
                                onName(speaker)
                            } label: {
                                Text(speaker.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.speakerColor(number: speaker.number))
                            }
                            .buttonStyle(.plain)
                            if speaker.name == nil {
                                Text("Tap to name")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(turn.segments[0].start.clockString)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                    ForEach(turn.segments) { segment in
                        segmentView(segment)
                    }
                }
            }
        }

        private func segmentView(_ segment: TranscriptSegment) -> some View {
            let isHighlighted = highlightedSegment == segment.id
            let count = sourceCounts[segment.id] ?? 0
            return VStack(alignment: .leading, spacing: 6) {
                Text(segment.text)
                    .fixedSize(horizontal: false, vertical: true)
                if count > 0 {
                    Chip(text: "Source of \(count) action\(count == 1 ? "" : "s")", systemImage: "quote.opening", tint: Theme.brand)
                }
            }
            .padding(isHighlighted ? 10 : 0)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHighlighted ? Theme.brand.opacity(0.10) : .clear)
            )
            .id(segment.id)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = segment.text
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                if !allSpeakers.isEmpty {
                    Menu {
                        ForEach(allSpeakers) { option in
                            Button(option.displayName) { onReassign(segment.id, option.id) }
                        }
                    } label: {
                        Label("Change speaker", systemImage: "person.crop.circle.badge.questionmark")
                    }
                }
            }
        }
    }

    // MARK: - Notes

    private var notesPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            CardHeader(title: "My notes", systemImage: "pencil.line", tint: Theme.brand)
            TextField("Add notes", text: $meeting.userNotes, axis: .vertical)
                .lineLimit(6...)
        }
        .cardStyle()
    }
}

/// Renders "- " lines as bullets and anything else as paragraphs.
private struct BulletList: View {
    var text: String

    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("- ") || line.hasPrefix("• ") {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("●")
                            .font(.system(size: 8))
                            .foregroundStyle(Theme.brand)
                        Text(LocalizedStringKey(String(line.dropFirst(2))))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(LocalizedStringKey(line))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// Shown while speakers are identified and notes are written.
private struct ProcessingCard: View {
    let meeting: Meeting

    private enum StepState {
        case done, active, pending
    }

    private var stage: ProcessingStage? { meeting.processingStage }
    private var showsSpeakerStep: Bool {
        stage == .speakers || !meeting.speakers.isEmpty || meeting.speakerNote != nil
    }
    private var progress: Double {
        switch stage {
        case .speakers: 0.4
        case .notes: 0.75
        case nil: 0.15
        }
    }
    private var wordCount: Int {
        meeting.segments.reduce(0) { $0 + $1.text.split(separator: " ").count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                CardHeader(title: "Preparing your notes", systemImage: "sparkles")
                ProgressView(value: progress)
                    .tint(Theme.brand)
                    .animation(.easeInOut, value: progress)
                step("Transcribed", detail: "\(meeting.duration.durationString) · \(wordCount) words", state: .done)
                if showsSpeakerStep {
                    step("Identifying speakers", detail: "Separating voices on this iPhone", state: stage == .speakers ? .active : .done)
                }
                step(
                    "Writing summary and actions",
                    detail: NotesEnhancers.isAppleIntelligenceAvailable ? "Apple Intelligence, on this iPhone" : "On this iPhone",
                    state: stage == .notes ? .active : .pending
                )
                Label("Audio is deleted as soon as speakers are identified.", systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .cardStyle()

            Text("You can leave this screen. Notes keep processing in the background.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    private func step(_ title: String, detail: String, state: StepState) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                switch state {
                case .done:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                case .active:
                    ProgressView()
                        .controlSize(.small)
                case .pending:
                    Circle()
                        .strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
            }
            .font(.title3)
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title + (state == .active ? "…" : ""))
                    .font(.body.weight(state == .pending ? .regular : .semibold))
                    .foregroundStyle(state == .pending ? Theme.textSecondary : Color.primary)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
