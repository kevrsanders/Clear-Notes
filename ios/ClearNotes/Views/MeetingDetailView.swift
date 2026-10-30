import SwiftData
import SwiftUI
import UIKit

struct MeetingDetailView: View {
    enum Pane: String, CaseIterable {
        case summary = "Summary"
        case actions = "Actions"
        case transcript = "Transcript"
        case notes = "Notes"
    }

    @Bindable var meeting: Meeting
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var pane: Pane = .summary
    @State private var highlightedSegment: UUID?
    @State private var newActionText = ""
    @State private var isRenaming = false
    @State private var draftTitle = ""
    @State private var confirmDelete = false

    private var visibleActions: [ActionItem] {
        meeting.actions
            .filter { $0.status != .dismissed }
            .sorted { lhs, rhs in
                if (lhs.status == .suggested) != (rhs.status == .suggested) { return lhs.status == .suggested }
                if (lhs.status == .done) != (rhs.status == .done) { return rhs.status == .done }
                return lhs.createdAt < rhs.createdAt
            }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    Picker("Section", selection: $pane) {
                        ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    switch pane {
                    case .summary: summaryPane
                    case .actions: actionsPane
                    case .transcript: transcriptPane
                    case .notes: notesPane
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .onChange(of: highlightedSegment) { _, id in
                guard let id else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(150))
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
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
                context.delete(meeting)
                dismiss()
            }
        } message: {
            Text("The transcript, notes and actions will be deleted from this iPhone.")
        }
    }

    // MARK: - Header and toolbar

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.title2.bold())
            Text("\(meeting.createdAt.formatted(date: .complete, time: .shortened)) · \(meeting.duration.durationString)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 8)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ShareLink(item: MarkdownExporter.markdown(for: meeting)) {
                    Label("Share notes", systemImage: "square.and.arrow.up")
                }
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
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var summaryPane: some View {
        switch meeting.processingState {
        case .processing:
            Card {
                HStack(spacing: 12) {
                    ProgressView()
                    Text("Writing your notes on this iPhone…")
                        .foregroundStyle(.secondary)
                }
            }
        case .failed:
            Card(title: "Notes couldn't be generated", systemImage: "exclamationmark.triangle") {
                Text(meeting.processingError ?? "Something went wrong.")
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await MeetingProcessor.process(meeting) }
                }
                .buttonStyle(.bordered)
            }
        case .ready:
            Card(title: "Summary", systemImage: "text.alignleft") {
                Text(LocalizedStringKey(meeting.summary.isEmpty ? "No summary." : meeting.summary))
            }
            if !meeting.decisions.isEmpty {
                Card(title: "Decisions", systemImage: "signpost.right") {
                    ForEach(meeting.decisions, id: \.self) { decision in
                        Label(decision, systemImage: "checkmark.seal")
                            .labelStyle(BulletLabelStyle())
                    }
                }
            }
            let suggested = meeting.actions.filter { $0.status == .suggested }.count
            if suggested > 0 {
                Button {
                    pane = .actions
                } label: {
                    Card {
                        HStack {
                            Image(systemName: "sparkles").foregroundStyle(.tint)
                            Text("\(suggested) suggested action\(suggested == 1 ? "" : "s") to review")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            if let source = meeting.insightsSource {
                Label("Generated by \(source). Check before sharing.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var actionsPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if visibleActions.isEmpty && meeting.processingState != .processing {
                Card {
                    Text("No actions yet. Add one below.")
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(visibleActions) { action in
                Card {
                    ActionRow(action: action, onShowSource: sourceHandler(for: action))
                }
            }
            Card {
                HStack {
                    TextField("Add an action", text: $newActionText)
                        .submitLabel(.done)
                        .onSubmit(addAction)
                    Button(action: addAction) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .disabled(newActionText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var transcriptPane: some View {
        Card {
            if meeting.segments.isEmpty {
                Text("Nothing was transcribed.")
                    .foregroundStyle(.secondary)
            }
            ForEach(meeting.segments) { segment in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(segment.start.clockString)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    Text(segment.text)
                        .textSelection(.enabled)
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(highlightedSegment == segment.id ? Color.accentColor.opacity(0.15) : .clear)
                )
                .id(segment.id)
            }
        }
    }

    private var notesPane: some View {
        Card(title: "My notes", systemImage: "pencil.line") {
            TextField("Add notes", text: $meeting.userNotes, axis: .vertical)
                .lineLimit(5...)
        }
    }

    /// Jumps to the transcript line an action came from, if it has one.
    private func sourceHandler(for action: ActionItem) -> (() -> Void)? {
        guard let id = action.sourceSegmentID else { return nil }
        return {
            pane = .transcript
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
}

/// A compact bullet-style label for lists inside cards.
private struct BulletLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            configuration.icon.foregroundStyle(.tint)
            configuration.title
        }
    }
}
