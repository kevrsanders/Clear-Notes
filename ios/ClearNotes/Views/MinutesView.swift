import SwiftData
import SwiftUI
import UIKit

/// The Minutes tab: formal minutes written like a minute-taker would, on request, which the user
/// can edit, copy or share.
struct MinutesPane: View {
    @Bindable var meeting: Meeting

    @State private var jobs = MinutesJobs.shared
    @State private var editing = false
    @State private var confirmRewrite = false
    @State private var copied = false

    private var progress: MinutesJobs.Progress? { jobs.progress(for: meeting) }
    private var suggestedCount: Int { meeting.actions.filter { $0.status == .suggested }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let progress {
                writingCard(progress)
            } else if meeting.minutesInProgress {
                // Paused while Clear Notes was in the background; carries on straight away.
                writingCard(MinutesJobs.Progress(part: 0, of: 1))
            } else if meeting.minutes.isEmpty {
                introCard
            } else {
                toolbar
                MinutesDocument(text: meeting.minutes)
                    .cardStyle()
                    .textSelection(.enabled)
                if let source = meeting.minutesSource {
                    Label(sourceLine(source), systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if progress == nil, suggestedCount > 0 {
                Label(
                    "\(suggestedCount) suggested action\(suggestedCount == 1 ? " isn't" : "s aren't") in the minutes. Accept \(suggestedCount == 1 ? "it" : "them") on the Actions tab, then rewrite the minutes.",
                    systemImage: "info.circle"
                )
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            }
        }
        .task {
            if meeting.minutesInProgress, progress == nil {
                jobs.write(meeting, fresh: false)
            }
        }
        .sheet(isPresented: $editing) {
            MinutesEditor(text: meeting.minutes) { meeting.minutes = $0 }
        }
        .confirmationDialog("Rewrite the minutes?", isPresented: $confirmRewrite, titleVisibility: .visible) {
            Button("Rewrite minutes") { jobs.write(meeting) }
        } message: {
            Text("They're written again from the transcript, decisions and accepted actions. Changes you've made to them will be replaced.")
        }
    }

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            CardHeader(title: "Minutes", systemImage: "doc.plaintext", tint: Theme.brand)
            Text("Formal minutes, written the way a minute-taker would: who was present, a numbered item for each part of the meeting in reported speech (\"Priya reported that…\"), what was agreed, the actions, and a summary of actions.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Written on this iPhone. You can edit them before sharing.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Button {
                jobs.write(meeting)
            } label: {
                Label("Write minutes", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(meeting.segments.isEmpty)
        }
        .cardStyle()
    }

    private func writingCard(_ progress: MinutesJobs.Progress) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ProgressView()
                Text(progress.of > 1 && progress.part > 0
                     ? "Writing item \(progress.part) of \(progress.of)…"
                     : "Writing the minutes…")
                    .font(.headline)
            }
            if progress.of > 1 {
                ProgressView(value: Double(max(progress.part - 1, 0)), total: Double(progress.of))
                    .tint(Theme.brand)
            }
            Text("This takes a little while for a long meeting. The screen stays on while this shows. If you leave Clear Notes, the minutes pause and carry on from the next item when you're back.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 12)
                        .frame(maxWidth: index % 3 == 2 ? 180 : CGFloat.infinity, alignment: .leading)
                }
            }
        }
        .cardStyle()
        // Auto-lock would put Clear Notes in the background, where Apple Intelligence pauses.
        .onAppear { ScreenAwake.hold() }
        .onDisappear { ScreenAwake.release() }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                editing = true
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            Button {
                UIPasteboard.general.string = meeting.minutes
                copied = true
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(SecondaryButtonStyle(compact: true))
            .sensoryFeedback(.success, trigger: copied)
            ShareLink(item: meeting.minutes, subject: Text("Minutes: \(meeting.title)")) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            Spacer(minLength: 0)
            Menu {
                Button {
                    confirmRewrite = true
                } label: {
                    Label("Rewrite minutes", systemImage: "arrow.clockwise")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("More")
        }
    }

    private func sourceLine(_ source: String) -> String {
        guard let date = meeting.minutesWrittenAt else { return source }
        return "\(source) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// Styles plain-text minutes: numbered items and points, Agreed and Action lines, and the summary
/// of actions. Anything else, e.g. a line the user added, is shown as a paragraph.
struct MinutesDocument: View {
    var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MinutesFormat.lines(from: text).enumerated()), id: \.offset) { index, line in
                row(line, isFirst: index == 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(_ line: MinutesLine, isFirst: Bool) -> some View {
        switch line {
        case .title(let title):
            Text(title)
                .font(.title3.bold())
                .fixedSize(horizontal: false, vertical: true)
        case .subtitle(let text):
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)
        case .labelled(let label, let text):
            (Text("\(label): ").fontWeight(.semibold) + Text(text))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number + ".")
                    .foregroundStyle(Theme.brand)
                    .monospacedDigit()
                Text(text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.headline)
            .padding(.top, 10)
        case .point(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 30, alignment: .leading)
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .agreed(let text):
            taggedRow(tag: "Agreed", tint: Theme.decision, text: text)
        case .action(let text):
            taggedRow(tag: "Action", tint: Theme.brand, text: text)
        case .section(let text):
            Text(text)
                .font(.headline)
                .padding(.top, 12)
        case .summaryAction(let number, let text):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(number)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.brand)
                    .frame(width: 30, alignment: .leading)
                Text(text)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .paragraph(let text):
            Text(text)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func taggedRow(tag: String, tint: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(tag.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(tint)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(tint.opacity(0.12), in: Capsule())
            Text(text)
                .font(.subheadline.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 38)
    }
}

/// Edits the minutes as plain text.
private struct MinutesEditor: View {
    @State var text: String
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TextEditor(text: $text)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .navigationTitle("Edit minutes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            onSave(text.trimmingCharacters(in: .whitespacesAndNewlines))
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
        }
    }
}
