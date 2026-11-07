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

/// The two ways to delete a meeting, as items in a menu: straight in the menu rather than a
/// submenu, which iOS stacks on top of the menu it opened from. Each says what it does.
struct DeleteChoices: View {
    var onMoveToRecentlyDeleted: () -> Void
    var onDeletePermanently: () -> Void

    var body: some View {
        Section {
            // In a menu, a second Text is the item's subtitle and an Image its icon.
            Button(action: onMoveToRecentlyDeleted) {
                Text("Move to Recently deleted")
                Text("You can restore it for 7 days")
                Image(systemName: "trash")
            }
            Button(role: .destructive, action: onDeletePermanently) {
                Text("Delete permanently")
                Text("Recording and all. Can't be undone")
                Image(systemName: "trash.slash")
            }
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
        .glass(in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}

/// Settings → Recently deleted: meetings deleted in the last week, which can be restored or
/// deleted for good straight away.
struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Meeting> { $0.deletedAt != nil }) private var deleted: [Meeting]
    @State private var confirmEmpty = false

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
        .background { GlowBackground() }
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
        .confirmationDialog(
            deleted.count == 1 ? "Delete this meeting for good?" : "Delete all \(deleted.count) for good?",
            isPresented: $confirmEmpty,
            titleVisibility: .visible
        ) {
            Button("Delete for good", role: .destructive) {
                let all = deleted
                withAnimation(.snappy) {
                    for meeting in all { RecentlyDeleted.deleteForGood(meeting, in: context) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Recordings, transcripts, notes and actions are deleted from this iPhone. This can't be undone.")
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
                // Opens right here, on the button, rather than at the bottom of the screen.
                Menu {
                    Button(role: .destructive) {
                        withAnimation(.snappy) { RecentlyDeleted.deleteForGood(meeting, in: context) }
                    } label: {
                        Text("Delete for good")
                        Text("Recording and all. Can't be undone")
                        Image(systemName: "trash.slash")
                    }
                } label: {
                    Text("Delete now")
                        .foregroundStyle(.red)
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
