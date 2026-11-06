import SwiftData
import SwiftUI
import UIKit

struct MeetingDetailView: View {
    enum Pane: Hashable {
        case overview, minutes, actions, transcript, notes
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
    @State private var followUp: FollowUpKind?
    @State private var playback = AudioPlayback()
    @State private var confirmDeleteAudio = false
    @State private var choosingSpeakerCount = false
    @State private var confirmImproveTranscript = false
    @State private var improveFailed = false
    @State private var editingSegment: TranscriptSegment?
    @State private var sharingFile = false
    /// Choosing transcript lines to move to another speaker together.
    @State private var selectingLines = false
    @State private var selectedLines: Set<UUID> = []
    @State private var lastSelectedLine: UUID?
    /// Lines waiting for the user to choose who said them.
    @State private var reassigning: ReassignRequest?
    /// The action being edited or assigned.
    @State private var editingAction: ActionItem?
    /// The player appears only when it's needed: full while playing, a small pill once paused.
    @State private var playerMode: PlayerMode = .hidden

    private enum PlayerMode {
        case hidden, full, mini
    }
    /// Accepting or dismissing every suggestion, waiting for the user to confirm.
    @State private var bulkReview: BulkReview?

    private enum BulkReview: Identifiable {
        case acceptAll, dismissAll
        var id: Self { self }
    }
    @AppStorage(SettingsKeys.myName) private var myName = ""
    @Query(sort: \Meeting.createdAt, order: .reverse) private var allMeetings: [Meeting]

    /// The last meeting in this meeting's series, for the Last time card.
    private var previousMeeting: Meeting? {
        MeetingSeries.previous(seriesID: meeting.seriesID, title: meeting.title, before: meeting.createdAt, in: allMeetings)
    }

    /// The transcript line being played, for highlighting.
    private var playingSegment: UUID? {
        guard playback.isPlaying else { return nil }
        let time = playback.currentTime
        return meeting.segments.last(where: { $0.start <= time })?.id
    }

    /// Plays the recording from a moment (to an optional end), when there is a recording.
    private var playHandler: ((TimeInterval, TimeInterval?) -> Void)? {
        guard playback.isLoaded else { return nil }
        return { start, end in playback.play(from: start, until: end) }
    }

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
                                .init(value: .minutes, title: "Minutes"),
                                .init(value: .actions, title: "Actions", badge: toReview.count),
                                .init(value: .transcript, title: "Transcript"),
                                .init(value: .notes, title: "Notes"),
                            ],
                            selection: $pane
                        )
                        switch pane {
                        case .overview: overviewPane
                        case .minutes: MinutesPane(meeting: meeting)
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
        .safeAreaInset(edge: .bottom) {
            if selectingLines {
                selectionBar
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if playback.isLoaded, playerMode == .full {
                PlayerBar(playback: playback, expiresAt: meeting.audioExpiresAt) {
                    playback.pause()
                    withAnimation(.snappy) { playerMode = .hidden }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if playback.isLoaded, playerMode == .mini {
                miniPlayer
                    .padding(.horizontal, 16)
                    .padding(.bottom, 6)
                    .transition(.scale(scale: 0.8, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        // Playing brings up the full player. A few seconds after pausing (or after the last
        // scrub while paused) it tucks itself away into the small pill.
        .task(id: "\(playback.isPlaying)-\(Int(playback.currentTime))") {
            if playback.isPlaying {
                if playerMode != .full { withAnimation(.snappy) { playerMode = .full } }
                return
            }
            guard playerMode == .full else { return }
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, !playback.isPlaying, playerMode == .full else { return }
            withAnimation(.snappy) { playerMode = .mini }
        }
        .task(id: meeting.audioFileName) {
            if let url = meeting.playableAudioURL {
                playback.load(url)
            } else {
                playback.unload()
            }
        }
        .onDisappear { playback.stop() }
        .confirmationDialog("How many people spoke?", isPresented: $choosingSpeakerCount, titleVisibility: .visible) {
            ForEach(2...8, id: \.self) { count in
                Button("\(count) people") {
                    Task { await MeetingProcessor.reidentifySpeakers(in: meeting, count: count) }
                }
            }
        } message: {
            Text("Clear Notes listens to the recording again and regroups the voices. Names are kept where a voice matches one you've named; any new voices need naming.")
        }
        .confirmationDialog("Improve the transcript?", isPresented: $confirmImproveTranscript, titleVisibility: .visible) {
            Button("Improve transcript") {
                Task {
                    let improved = await MeetingProcessor.improveTranscript(of: meeting)
                    if !improved { improveFailed = true }
                }
            }
        } message: {
            Text("Transcribes the recording again with the more accurate model on this iPhone. Speaker names are kept; any lines you edited are replaced.")
        }
        .alert("The transcript couldn't be improved", isPresented: $improveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The live transcript has been kept. Check the recording is still on this iPhone and try again later.")
        }
        .sheet(isPresented: $sharingFile) {
            ShareMeetingSheet(meeting: meeting)
        }
        .confirmationDialog(
            bulkReview == .dismissAll ? "Dismiss all \(toReview.count) suggestions?" : "Accept all \(toReview.count) suggestions?",
            isPresented: Binding(get: { bulkReview != nil }, set: { if !$0 { bulkReview = nil } }),
            titleVisibility: .visible,
            presenting: bulkReview
        ) { review in
            switch review {
            case .acceptAll:
                Button("Accept all") { withAnimation(.snappy) { meeting.reviewAllSuggestions(accept: true) } }
            case .dismissAll:
                Button("Dismiss all", role: .destructive) { withAnimation(.snappy) { meeting.reviewAllSuggestions(accept: false) } }
            }
        } message: { review in
            Text(review == .acceptAll
                 ? "They become open actions. You can still edit, reassign or tick them off one by one."
                 : "They're removed from the list. Actions you've accepted or marked aren't affected.")
        }
        .sheet(item: $editingAction) { action in
            ActionEditor(action: action, people: (action.meeting ?? meeting).assignablePeople(myName: myName))
                .presentationDetents([.large])
        }
        // A dialog rather than a submenu: it stays put while the transcript redraws (e.g. during playback).
        .confirmationDialog(
            reassigning.map { $0.segmentIDs.count == 1 ? "Who said this line?" : "Who said these \($0.segmentIDs.count) lines?" } ?? "",
            isPresented: Binding(get: { reassigning != nil }, set: { if !$0 { reassigning = nil } }),
            titleVisibility: .visible,
            presenting: reassigning
        ) { request in
            ForEach(speakerChoices(for: request)) { speaker in
                Button(speaker.displayName) { reassign(request, to: speaker.id) }
            }
            Button("New speaker") {
                let speaker = meeting.addSpeaker()
                reassign(request, to: speaker.id)
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: pane) { _, _ in endSelecting() }
        .sheet(item: $editingSegment) { segment in
            LineEditor(text: segment.text) { newText in
                meeting.editSegmentText(segment.id, to: newText)
            }
            .presentationDetents([.medium])
            .presentationCornerRadius(32)
        }
        .confirmationDialog("Delete the recording?", isPresented: $confirmDeleteAudio, titleVisibility: .visible) {
            Button("Delete recording", role: .destructive) {
                playback.unload()
                meeting.deleteAudio()
            }
        } message: {
            Text("The transcript and notes are kept. Only the audio is deleted.")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(item: $followUp) { kind in
            FollowUpSheet(kind: kind, meeting: meeting)
                .presentationDetents([.large])
                .presentationCornerRadius(32)
        }
        .sheet(item: $namingSpeaker) { speaker in
            SpeakerNamingSheet(meeting: meeting, speaker: speaker, onPlay: playHandler)
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
                playback.unload()
                meeting.deleteAllAudio()
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
                if meeting.teamsJoinURL != nil {
                    Chip(text: "Teams meeting", systemImage: "video.fill")
                }
                if playback.isLoaded {
                    Button {
                        if playback.isPlaying {
                            playback.pause()
                        } else {
                            playback.play()
                        }
                    } label: {
                        ActionChip(
                            text: playback.isPlaying ? "Playing" : "Play recording",
                            systemImage: playback.isPlaying ? "pause.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(playback.isPlaying ? "Pause recording" : "Play recording")
                }
                let series = MeetingSeries.all(like: meeting, in: allMeetings)
                if series.count > 1 {
                    NavigationLink {
                        SeriesListView(meeting: meeting)
                    } label: {
                        Chip(text: "\(series.count) in this series", systemImage: "repeat", tint: Theme.brand)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows every meeting in this series")
                }
                if meeting.importedAt != nil {
                    Chip(text: meeting.sharedBy.map { "Shared by \($0)" } ?? "Shared with you", systemImage: "tray.and.arrow.down.fill")
                }
                Chip(text: "On-device", systemImage: "lock.fill", tint: Theme.brand)
            }
            if !meeting.attendees.isEmpty {
                Text("Invited: " + meeting.attendees.joined(separator: ", "))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.top, 4)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Menu {
                Button {
                    sharingFile = true
                } label: {
                    Label("Share meeting with a Clear Notes user", systemImage: "square.and.arrow.up.on.square")
                }
                ShareLink(item: MarkdownExporter.markdown(for: meeting)) {
                    Label("Share as text", systemImage: "text.alignleft")
                }
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .accessibilityLabel("Share")
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
                if AccurateTranscriber.isReady && meeting.playableAudioURL != nil {
                    Button {
                        confirmImproveTranscript = true
                    } label: {
                        Label("Improve transcript", systemImage: "text.badge.checkmark")
                    }
                    .disabled(meeting.processingState == .processing)
                }
                Divider()
                if meeting.audioFileName != nil {
                    Button(role: .destructive) {
                        confirmDeleteAudio = true
                    } label: {
                        Label("Delete recording", systemImage: "waveform.slash")
                    }
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete meeting", systemImage: "trash")
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
                                    if let share = talkShares[speaker.id] {
                                        Text("\(Int((share * 100).rounded()))%")
                                            .font(.caption2.weight(.semibold).monospacedDigit())
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    if speaker.name == nil {
                                        Text(speaker.suggestedName.map { "\($0)?" } ?? "Tap to name")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Theme.brand)
                                    } else if speaker.matchedProfileID != nil {
                                        Text("Recognised")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                }
                                .frame(minWidth: 56)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(speaker.name == nil ? "Name \(speaker.displayName)" : "Rename \(speaker.displayName)")
                        }
                    }
                }
                if !talkShares.isEmpty {
                    talkTimeBar
                }
                if meeting.playableAudioURL != nil && SpeakerSeparators.isSupported {
                    Button {
                        choosingSpeakerCount = true
                    } label: {
                        Label("Wrong number of speakers?", systemImage: "person.2.badge.gearshape")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardStyle(padding: 16)
        } else if let note = meeting.speakerNote {
            VStack(alignment: .leading, spacing: 8) {
                Label(note, systemImage: "person.2.slash")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                if meeting.playableAudioURL != nil && SpeakerSeparators.isSupported {
                    Button("Identify speakers") { choosingSpeakerCount = true }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                }
            }
        }

        if meeting.notesNeedRefresh {
            HStack(spacing: 12) {
                Text("The transcript or speaker names changed. Refresh the notes to use them.")
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

    // MARK: - Talk time

    private var talkShares: [String: Double] {
        TalkTime.shares(meeting.talkTime)
    }

    /// One coloured segment per speaker, sized by their share of talk time.
    private var talkTimeBar: some View {
        let shares = talkShares
        let speaking = meeting.speakers.filter { (shares[$0.id] ?? 0) > 0 }
        let total = meeting.talkTime.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geometry in
                let available = geometry.size.width - CGFloat(max(speaking.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(speaking) { speaker in
                        Capsule()
                            .fill(Theme.speakerColor(number: speaker.number))
                            .frame(width: max(4, available * CGFloat(shares[speaker.id] ?? 0)))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .accessibilityElement()
            .accessibilityLabel(speaking.map { "\($0.displayName) \(Int(((shares[$0.id] ?? 0) * 100).rounded())) percent" }.joined(separator: ", "))

            Text("Talk time · \(total.durationString)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 4)
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

            if meeting.processingState == .ready, let caveat = meeting.notesCaveat {
                VStack(alignment: .leading, spacing: 12) {
                    CardHeader(title: "About these notes", systemImage: "info.circle.fill", tint: Theme.warning)
                    Text(caveat)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if NotesEnhancers.isAppleIntelligenceAvailable {
                        Button("Try Apple Intelligence again") {
                            Task { await MeetingProcessor.process(meeting) }
                        }
                        .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                }
                .cardStyle()
            }

            document
            if let previousMeeting {
                lastTimeCard(previousMeeting)
            }
            followUps

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

    /// Summary, topics and decisions on one surface, so the notes read like a page.
    private var document: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 14) {
                CardHeader(title: "Summary", systemImage: "sparkles")
                BulletList(text: meeting.summary.isEmpty ? "No summary yet." : meeting.summary)
            }

            if !meeting.topics.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 16) {
                    CardHeader(title: "Topics", systemImage: "list.bullet.rectangle.portrait")
                    ForEach(meeting.topics) { topic in
                        Button {
                            jump(to: topic)
                        } label: {
                            TopicRow(topic: topic)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens the transcript at this point")
                    }
                }
            }

            if !meeting.decisions.isEmpty {
                Divider()
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
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button {
                                withAnimation(.snappy) { meeting.makeAction(fromDecisionAt: index) }
                            } label: {
                                Label("Make it an action", systemImage: "checklist")
                            }
                        }
                    }
                    Text("Hold a decision to make it an action.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .cardStyle(padding: 22)
    }

    /// The previous meeting in the series: a short summary, the actions it left open, and a link.
    private func lastTimeCard(_ previous: Meeting) -> some View {
        let points = NotesText.bullets(from: previous.summary).prefix(3)
        let open = previous.actions
            .filter { $0.status == .open }
            .sorted { $0.createdAt < $1.createdAt }
        return VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Last time · " + LastTime.dateText(previous.createdAt), systemImage: "clock.arrow.circlepath")
            if !points.isEmpty {
                BulletList(text: points.map { "- \($0)" }.joined(separator: "\n"))
            }
            if !open.isEmpty {
                Text(open.count == 1 ? "1 action still open from last time" : "\(open.count) actions still open from last time")
                    .font(.subheadline.weight(.semibold))
                ForEach(open) { action in
                    ActionCard(action: action, onEdit: { editingAction = action })
                }
            } else if !previous.actions.isEmpty {
                Label("Every action from last time is done.", systemImage: "checkmark.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.success)
            }
            HStack(spacing: 16) {
                NavigationLink(value: previous) {
                    Label("Open last meeting", systemImage: "arrow.right.circle")
                }
                NavigationLink {
                    SeriesListView(meeting: meeting)
                } label: {
                    Label("All in this series", systemImage: "repeat")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.brand)
            .buttonStyle(.plain)
        }
        .cardStyle(padding: 22)
    }

    private var followUps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Follow-ups")
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(FollowUpKind.allCases.enumerated()), id: \.element) { index, kind in
                    if index > 0 {
                        Divider().padding(.leading, 52)
                    }
                    Button {
                        followUp = kind
                    } label: {
                        HStack(spacing: 12) {
                            IconTile(systemName: kind.systemImage, tint: FollowUpStyle.tint(for: kind), size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.title)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text(kind.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.bold))
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .cardStyle(padding: 14)
        }
    }

    /// Opens the transcript at the first line of a topic.
    private func jump(to topic: Topic) {
        guard let segment = meeting.segments.first(where: { $0.end > topic.start }) else { return }
        withAnimation(.snappy) { pane = .transcript }
        highlightedSegment = segment.id
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
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(title)
                Spacer(minLength: 8)
                // Suggestions can be many in a long meeting, so they can be cleared together.
                if items.count > 1, items.allSatisfy({ $0.status == .suggested }) {
                    Button("Accept all") { bulkReview = .acceptAll }
                    Text("·")
                        .foregroundStyle(Theme.textTertiary)
                    Button("Dismiss all") { bulkReview = .dismissAll }
                }
            }
            .font(.footnote.weight(.semibold))
            .tint(Theme.brand)
            .padding(.top, 6)
            ForEach(items) { action in
                ActionCard(
                    action: action,
                    onShowSource: sourceHandler(for: action),
                    onMakeDecision: { meeting.makeDecision(from: action) },
                    onEdit: { editingAction = action }
                )
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
            } else if !meeting.speakers.isEmpty {
                HStack {
                    Text(selectingLines ? "Tap lines to select. Hold a line to select up to it." : "Hold a line to change its speaker.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer(minLength: 8)
                    Button(selectingLines ? "Done" : "Select lines") {
                        if selectingLines { endSelecting() } else { startSelecting(nil) }
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(Theme.brand)
                }
            }
            let counts = sourceCounts
            // Reading the revision makes speaker edits redraw the transcript straight away.
            let revision = meeting.revision
            let playing = playingSegment
            ForEach(turns) { turn in
                let ids = Set(turn.segments.map(\.id))
                TurnView(
                    turn: turn,
                    speaker: meeting.speaker(withID: turn.speakerID),
                    showsAvatars: !meeting.speakers.isEmpty,
                    canChangeSpeaker: !meeting.speakers.isEmpty,
                    // Only what concerns this turn, so the other turns don't redraw during playback.
                    highlightedSegment: highlightedSegment.flatMap { ids.contains($0) ? $0 : nil },
                    playingSegment: playing.flatMap { ids.contains($0) ? $0 : nil },
                    sourceCounts: counts.filter { ids.contains($0.key) },
                    isSelecting: selectingLines,
                    selected: selectedLines.intersection(ids),
                    canPlay: playHandler != nil,
                    onName: { namingSpeaker = $0 },
                    onChangeSpeaker: { segmentID in
                        pausePlayback()
                        reassigning = ReassignRequest(segmentIDs: [segmentID])
                    },
                    onStartSelecting: { startSelecting($0) },
                    onToggle: { toggleLine($0) },
                    onSelectThrough: { selectThrough($0) },
                    onEdit: { editingSegment = $0 },
                    onPlay: playHandler
                )
                .equatable()
                .id("\(turn.id)-\(revision)")
            }
        }
        .padding(.top, 4)
    }

    /// The paused player, out of the way in the corner. Tap it to open the full player.
    private var miniPlayer: some View {
        HStack {
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button(action: playback.togglePlayback) {
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.brandGradient, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(playback.isPlaying ? "Pause recording" : "Play recording")
                Text("\(playback.currentTime.clockString) / \(playback.duration.clockString)")
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.primary)
            }
            .padding(.leading, 6)
            .padding(.trailing, 14)
            .padding(.vertical, 6)
            .glass(in: Capsule())
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.snappy) { playerMode = .full } }
            .accessibilityAction(named: "Show player") { playerMode = .full }
        }
    }

    // MARK: - Choosing lines and who said them

    private struct ReassignRequest: Identifiable {
        let id = UUID()
        let segmentIDs: Set<UUID>
    }

    /// Everyone for several lines; everyone except the current speaker for one line.
    private func speakerChoices(for request: ReassignRequest) -> [Speaker] {
        let sorted = meeting.speakers.sorted { $0.number < $1.number }
        guard request.segmentIDs.count == 1, let id = request.segmentIDs.first,
              let current = meeting.segments.first(where: { $0.id == id })?.speakerID
        else { return sorted }
        return sorted.filter { $0.id != current }
    }

    private func reassign(_ request: ReassignRequest, to speakerID: String) {
        meeting.reassignSegments(request.segmentIDs, to: speakerID)
        endSelecting()
    }

    private func pausePlayback() {
        if playback.isPlaying { playback.pause() }
    }

    private func startSelecting(_ first: UUID?) {
        pausePlayback()
        withAnimation(.snappy) {
            selectingLines = true
            selectedLines = first.map { Set([$0]) } ?? []
            lastSelectedLine = first
        }
    }

    private func endSelecting() {
        guard selectingLines || !selectedLines.isEmpty else { return }
        withAnimation(.snappy) {
            selectingLines = false
            selectedLines = []
            lastSelectedLine = nil
        }
    }

    private func toggleLine(_ id: UUID) {
        if selectedLines.contains(id) {
            selectedLines.remove(id)
        } else {
            selectedLines.insert(id)
            lastSelectedLine = id
        }
    }

    /// Selects every line from the last one tapped to this one, for a stretch of lines.
    private func selectThrough(_ id: UUID) {
        let order = meeting.segments.map(\.id)
        guard let anchor = lastSelectedLine, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: id) else {
            toggleLine(id)
            return
        }
        selectedLines.formUnion(order[min(from, to)...max(from, to)])
        lastSelectedLine = id
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Button("Cancel") { endSelecting() }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: 0)
            Text("\(selectedLines.count) selected")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Spacer(minLength: 0)
            Button {
                reassigning = ReassignRequest(segmentIDs: selectedLines)
            } label: {
                Label("Change speaker", systemImage: "person.crop.circle.badge.questionmark")
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .disabled(selectedLines.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(in: Capsule())
    }

    /// One speaker's consecutive lines. Equatable on its data, so a turn only redraws when
    /// something in it changes, not on every playback tick elsewhere in the transcript.
    private struct TurnView: View, Equatable {
        var turn: Turn
        var speaker: Speaker?
        var showsAvatars: Bool
        var canChangeSpeaker: Bool
        var highlightedSegment: UUID?
        var playingSegment: UUID?
        var sourceCounts: [UUID: Int]
        var isSelecting: Bool
        var selected: Set<UUID>
        var canPlay: Bool
        var onName: (Speaker) -> Void
        var onChangeSpeaker: (UUID) -> Void
        var onStartSelecting: (UUID) -> Void
        var onToggle: (UUID) -> Void
        var onSelectThrough: (UUID) -> Void
        var onEdit: (TranscriptSegment) -> Void
        /// Plays the recording between two times, when the recording is kept.
        var onPlay: ((TimeInterval, TimeInterval?) -> Void)?

        static func == (lhs: TurnView, rhs: TurnView) -> Bool {
            lhs.turn.segments == rhs.turn.segments
                && lhs.speaker == rhs.speaker
                && lhs.showsAvatars == rhs.showsAvatars
                && lhs.canChangeSpeaker == rhs.canChangeSpeaker
                && lhs.highlightedSegment == rhs.highlightedSegment
                && lhs.playingSegment == rhs.playingSegment
                && lhs.sourceCounts == rhs.sourceCounts
                && lhs.isSelecting == rhs.isSelecting
                && lhs.selected == rhs.selected
                && lhs.canPlay == rhs.canPlay
        }

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
                            .disabled(isSelecting)
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

        @ViewBuilder
        private func segmentView(_ segment: TranscriptSegment) -> some View {
            if isSelecting {
                selectableLine(segment)
            } else {
                line(segment)
                    .contextMenu {
                        if canPlay, let onPlay {
                            Button {
                                onPlay(segment.start, segment.end)
                            } label: {
                                Label("Play this line", systemImage: "play.fill")
                            }
                            Button {
                                onPlay(segment.start, nil)
                            } label: {
                                Label("Play from here", systemImage: "forward.fill")
                            }
                        }
                        if canChangeSpeaker {
                            Button {
                                onChangeSpeaker(segment.id)
                            } label: {
                                Label("Change speaker…", systemImage: "person.crop.circle.badge.questionmark")
                            }
                            Button {
                                onStartSelecting(segment.id)
                            } label: {
                                Label("Select lines…", systemImage: "checkmark.circle")
                            }
                        }
                        Button {
                            UIPasteboard.general.string = segment.text
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                        Button {
                            onEdit(segment)
                        } label: {
                            Label("Edit text", systemImage: "pencil")
                        }
                    }
            }
        }

        private func line(_ segment: TranscriptSegment) -> some View {
            let isHighlighted = highlightedSegment == segment.id
            let isPlaying = playingSegment == segment.id
            let count = sourceCounts[segment.id] ?? 0
            return VStack(alignment: .leading, spacing: 6) {
                Text(segment.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(isPlaying ? Theme.brand : Color.primary)
                    .onTapGesture { onPlay?(segment.start, segment.end) }
                    .accessibilityHint(onPlay == nil ? "" : "Plays this line")
                if count > 0 {
                    Chip(text: "Source of \(count) action\(count == 1 ? "" : "s")", systemImage: "quote.opening", tint: Theme.brand)
                }
            }
            // Constant padding: the highlight mustn't move lines under the user's finger.
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isHighlighted || isPlaying ? Theme.brand.opacity(0.10) : .clear)
            )
            .padding(.horizontal, -8)
            .animation(.easeOut(duration: 0.2), value: isPlaying)
            .id(segment.id)
        }

        /// In selection mode: tap to select or deselect, hold to select every line up to this one.
        private func selectableLine(_ segment: TranscriptSegment) -> some View {
            let isSelected = selected.contains(segment.id)
            return HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Theme.brand : Theme.textTertiary)
                    .font(.body)
                Text(segment.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Theme.brand.opacity(0.10) : .clear)
            )
            .padding(.horizontal, -8)
            .contentShape(Rectangle())
            .onTapGesture { onToggle(segment.id) }
            .onLongPressGesture { onSelectThrough(segment.id) }
            .sensoryFeedback(.selection, trigger: isSelected)
            .id(segment.id)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint("Double-tap to select. Hold to select every line up to this one.")
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
struct BulletList: View {
    var text: String

    /// One bullet per point, including points written on one line ("- A. - B."), so notes
    /// written before that was fixed show properly too.
    private var lines: [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap { line -> [String] in
                guard line.hasPrefix("- ") || line.hasPrefix("• ") else { return [line] }
                return NotesText.splitRunTogether(String(line.dropFirst(2))).map { "- " + $0 }
            }
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
    private var showsTranscriptStep: Bool {
        stage == .transcript || meeting.transcriptImproved
    }
    private var progress: Double {
        ProcessingProgress.fraction(stage: stage, partsDone: meeting.notesPartsDone, partsTotal: meeting.notesPartsTotal)
    }
    private var notesDetail: String {
        let engine = NotesEnhancers.isAppleIntelligenceAvailable ? "Apple Intelligence, on this iPhone" : "On this iPhone"
        guard stage == .notes,
              let part = ProcessingProgress.notesDetail(partsDone: meeting.notesPartsDone, partsTotal: meeting.notesPartsTotal)
        else { return engine }
        return "\(part) · \(engine)"
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
                if showsTranscriptStep {
                    step(
                        "Improving the transcript",
                        detail: "A second, more accurate pass on this iPhone",
                        state: stage == .transcript ? .active : .done
                    )
                }
                if showsSpeakerStep {
                    step("Identifying speakers", detail: "Separating voices on this iPhone", state: stage == .speakers ? .active : .done)
                }
                step(
                    "Writing summary and actions",
                    detail: notesDetail,
                    state: stage == .notes ? .active : .pending
                )
                Label(AudioRetention.current.promise, systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .cardStyle()

            Text(footnote)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
        // Auto-lock would put Clear Notes in the background, where iOS pauses it, so the screen
        // stays on while this card is showing.
        .onAppear { ScreenAwake.hold() }
        .onDisappear { ScreenAwake.release() }
    }

    private var footnote: String {
        var text = "Quickest with Clear Notes open: the screen stays on while this shows."
        if #available(iOS 26.0, *) {
            text += " If you leave, iOS may let it carry on for a while, with progress on your Lock Screen."
        }
        return text + " If iOS pauses it, it carries on from where it stopped when you come back."
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

/// A topic: time range, title and a few points.
private struct TopicRow: View {
    let topic: Topic

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(topic.start.clockString)–\(topic.end.clockString)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(Theme.brand)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Theme.brand.opacity(0.12), in: Capsule())
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(topic.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            ForEach(topic.points, id: \.self) { point in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•")
                        .foregroundStyle(Theme.textTertiary)
                    Text(point)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Floating glass player for the meeting's recording.
private struct PlayerBar: View {
    let playback: AudioPlayback
    let expiresAt: Date?
    /// Stops playback and hides the player.
    var onClose: () -> Void

    private var keptUntil: String {
        guard let expiresAt else { return "Kept until you delete it" }
        return "Kept until " + expiresAt.formatted(.dateTime.day().month(.abbreviated))
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: playback.togglePlayback) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Theme.brandGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Pause recording" : "Play recording")

            VStack(spacing: 2) {
                Slider(
                    value: Binding(get: { playback.currentTime }, set: { playback.seek(to: $0) }),
                    in: 0...max(playback.duration, 1)
                )
                .tint(Theme.brand)
                .accessibilityLabel("Position")
                HStack {
                    Text(playback.currentTime.clockString)
                    Spacer()
                    Text(keptUntil)
                        .lineLimit(1)
                    Spacer()
                    Text(playback.duration.clockString)
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
            }

            Button(action: playback.cycleRate) {
                Text(playback.rate == 1 ? "1×" : String(format: "%g×", playback.rate))
                    .font(.footnote.weight(.bold).monospacedDigit())
                    .frame(width: 44, height: 32)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Playback speed")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close player")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .glass(in: RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// Corrects the words of one transcript line.
private struct LineEditor: View {
    @State var text: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
                .padding(Theme.gutter)
                .background(Theme.background)
                .navigationTitle("Edit line")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text)
                            dismiss()
                        }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .onAppear { focused = true }
        }
    }
}
