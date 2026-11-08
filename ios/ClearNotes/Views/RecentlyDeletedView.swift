import SwiftData
import SwiftUI

/// The meeting just deleted, so the meetings list can offer Undo for a few seconds.
@MainActor
@Observable
final class DeletionUndo {
    static let shared = DeletionUndo()

    private(set) var meeting: Meeting?
    /// Changes on every delete, so the Undo bar's timer starts again.
    private(set) var token = UUID()

    func didDelete(_ meeting: Meeting) {
        self.meeting = meeting
        token = UUID()
    }

    func undo() {
        meeting?.restoreFromRecentlyDeleted()
        meeting = nil
    }

    func dismiss() {
        meeting = nil
    }
}

/// The two ways to delete a meeting, on one card of a menu sheet. Each says what it does.
struct DeleteChoices: View {
    var onMoveToRecentlyDeleted: () -> Void
    var onDeletePermanently: () -> Void

    var body: some View {
        MenuGroup {
            MenuRow(
                "Move to Recently deleted",
                subtitle: "You can restore it for 7 days",
                systemImage: "trash",
                action: onMoveToRecentlyDeleted
            )
            MenuRow(
                "Delete permanently",
                subtitle: "Recording and all. Can't be undone",
                systemImage: "trash.slash",
                role: .destructive,
                action: onDeletePermanently
            )
        }
    }
}

/// "Moved to Recently deleted · Undo", shown for a few seconds after a delete.
struct UndoBar: View {
    var onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "trash")
                .foregroundStyle(Theme.textSecondary)
            Text("Moved to Recently deleted")
                .font(.subheadline)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button("Undo", action: onUndo)
                .font(.subheadline.weight(.bold))
                .tint(Theme.brand)
        }
        .padding(.horizontal, 16)
        .frame(height: 50)
        .panel(in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

/// Settings → Recently deleted: meetings deleted in the last week, which can be restored or
/// deleted for good straight away.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Meeting> { $0.deletedAt != nil }) private var deleted: [Meeting]
    @State private var confirmEmpty = false
    /// The meeting whose "Delete now" was tapped.
    @State private var deletingNow: Meeting?

    private var newestFirst: [Meeting] {
        deleted.sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Deleted meetings are kept here for 7 days, recording included, then deleted for good.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
                if deleted.isEmpty {
                    ContentUnavailableView(
                        "Nothing recently deleted",
                        systemImage: "trash",
                        description: Text("Meetings you delete stay here for 7 days, so you can restore them.")
                    )
                    .padding(.top, 40)
                }
                ForEach(newestFirst) { meeting in
                    row(meeting)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .background { ScreenBackground() }
        .navigationTitle("Recently deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !deleted.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Empty", role: .destructive) { confirmEmpty = true }
                        .tint(.red)
                }
            }
        }
        .menuSheet(isPresented: $confirmEmpty) {
            MenuSheet(
                deleted.count == 1 ? "Delete this meeting for good?" : "Delete all \(deleted.count) for good?",
                message: "Recordings, transcripts, notes and actions are deleted from this iPhone. This can't be undone."
            ) {
                MenuGroup {
                    MenuRow("Delete for good", systemImage: "trash.slash", role: .destructive) {
                        let all = deleted
                        withAnimation(.snappy) {
                            for meeting in all { RecentlyDeleted.deleteForGood(meeting, in: context) }
                        }
                    }
                }
                MenuCancelButton()
            }
        }
        .menuSheet(item: $deletingNow) { meeting in
            MenuSheet(meeting.title) {
                MenuGroup {
                    MenuRow(
                        "Delete for good",
                        subtitle: "Recording and all. Can't be undone",
                        systemImage: "trash.slash",
                        role: .destructive
                    ) {
                        withAnimation(.snappy) { RecentlyDeleted.deleteForGood(meeting, in: context) }
                    }
                }
                MenuCancelButton()
            }
        }
        .task { RecentlyDeleted.purgeExpired(in: context) }
    }

    private func row(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(meeting.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())) · \(meeting.duration.durationString)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            Text(meeting.title)
                .font(.headline)
                .lineLimit(2)
            if let deletedAt = meeting.deletedAt {
                Text(RecentlyDeleted.statusLine(deletedAt))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.warning)
            }
            HStack(spacing: 10) {
                Button {
                    withAnimation(.snappy) { meeting.restoreFromRecentlyDeleted() }
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
                Button {
                    deletingNow = meeting
                } label: {
                    Text("Delete now")
                        .foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
