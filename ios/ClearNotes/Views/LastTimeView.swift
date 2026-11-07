import SwiftUI

/// The previous meeting in a series: what was said, what was decided and what's still to do.
/// Actions can be ticked off here, e.g. when someone reports one done during this meeting.
struct LastTimeView: View {
    let meeting: Meeting
    /// When set, a button opens the full previous meeting.
    var onOpenMeeting: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    private var actions: [ActionItem] {
        let reviewed = meeting.actions.filter { $0.status == .open || $0.status == .done }
        // Still-open actions first, as they're what to follow up.
        return reviewed.sorted { first, second in
            if (first.status == .open) != (second.status == .open) { return first.status == .open }
            return first.createdAt < second.createdAt
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("Last time · " + LastTime.dateText(meeting.createdAt))
                    Text(meeting.title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 8)
                .padding(.trailing, 48)

                if !meeting.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Summary", systemImage: "sparkles")
                        BulletList(text: meeting.summary)
                    }
                    .cardStyle()
                }

                if !meeting.decisions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        CardHeader(title: "Decisions", systemImage: "signpost.right.fill", tint: Theme.decision)
                        BulletList(text: meeting.decisions.map { "- \($0)" }.joined(separator: "\n"))
                    }
                    .cardStyle()
                }

                if !actions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(LastTime.actionsText(meeting))
                            .padding(.horizontal, 4)
                        ForEach(actions) { action in
                            ActionCard(action: action)
                        }
                    }
                }

                if meeting.summary.isEmpty && meeting.decisions.isEmpty && actions.isEmpty {
                    Text("No notes were kept for this meeting.")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .cardStyle()
                }

                if let onOpenMeeting {
                    Button {
                        onOpenMeeting()
                    } label: {
                        Label("Open the full meeting", systemImage: "arrow.right.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding(Theme.gutter)
        }
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            GlassCircleButton(systemName: "xmark", accessibilityLabel: "Close") { dismiss() }
                .padding(16)
        }
    }
}

/// Wording shared by the places that show the previous meeting.
enum LastTime {
    /// "Tue 27 Oct"
    static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    static func openActionCount(_ meeting: Meeting) -> Int {
        meeting.actions.filter { $0.status == .open }.count
    }

    /// "3 actions still open" or "All 4 actions done"
    static func actionsText(_ meeting: Meeting) -> String {
        let open = openActionCount(meeting)
        let done = meeting.actions.filter { $0.status == .done }.count
        if open == 0 { return done == 1 ? "1 action, done" : "All \(done) actions done" }
        return open == 1 ? "1 action still open" : "\(open) actions still open"
    }

    /// "Last time · Tue 27 Oct · 3 open actions"
    static func summaryLine(_ meeting: Meeting) -> String {
        let open = openActionCount(meeting)
        var parts = ["Last time", dateText(meeting.createdAt)]
        if open > 0 { parts.append(open == 1 ? "1 open action" : "\(open) open actions") }
        return parts.joined(separator: " · ")
    }
}
