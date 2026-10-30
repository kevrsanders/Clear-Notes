import SwiftData
import SwiftUI

/// Every action across all meetings, filtered by To review, Open and Done.
struct ActionsView: View {
    enum Filter: Hashable {
        case review, open, done
    }

    @Query(sort: \ActionItem.createdAt, order: .reverse) private var actions: [ActionItem]
    @State private var filter: Filter = .review
    @State private var path: [Meeting] = []

    private var suggested: [ActionItem] { actions.filter { $0.status == .suggested } }
    private var open: [ActionItem] { actions.filter { $0.status == .open } }
    private var done: [ActionItem] { actions.filter { $0.status == .done } }

    private var shown: [ActionItem] {
        switch filter {
        case .review: suggested
        case .open: open
        case .done: Array(done.prefix(100))
        }
    }

    private var subtitle: String {
        let meetings = Set(open.compactMap { $0.meeting?.persistentModelID }).count
        return "\(open.count) open across \(meetings) meeting\(meetings == 1 ? "" : "s")"
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Actions")
                            .font(.system(size: 34, weight: .bold))
                            .tracking(-0.6)
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 12)

                    PillTabs<Filter>(
                        items: [
                            .init(value: .review, title: "To review", badge: suggested.count),
                            .init(value: .open, title: "Open", badge: open.count),
                            .init(value: .done, title: "Done"),
                        ],
                        selection: $filter
                    )

                    if shown.isEmpty {
                        emptyState
                    } else {
                        if filter == .review {
                            Label("Suggested by AI from your transcripts. Accept the ones that are right.", systemImage: "sparkles")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(shown) { action in
                            ActionCard(action: action, onOpenMeeting: action.meeting.map { meeting in
                                { path.append(meeting) }
                            })
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
                .animation(.snappy, value: shown.map(\.persistentModelID))
            }
            .background { GlowBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Meeting.self) { MeetingDetailView(meeting: $0) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            IconTile(systemName: filter == .done ? "checkmark" : "checklist", tint: nil, size: 52)
            Text(emptyTitle)
                .font(.headline)
            Text("Actions from your meetings appear here so nothing gets forgotten.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 28)
    }

    private var emptyTitle: String {
        switch filter {
        case .review: "Nothing to review"
        case .open: "No open actions"
        case .done: "Nothing done yet"
        }
    }
}
