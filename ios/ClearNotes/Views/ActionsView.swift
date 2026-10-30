import SwiftData
import SwiftUI

/// Every action across all meetings: suggestions to review, open and recently done.
struct ActionsView: View {
    @Query(sort: \ActionItem.createdAt, order: .reverse) private var actions: [ActionItem]
    @State private var showDone = false
    @State private var path: [Meeting] = []

    private var suggested: [ActionItem] { actions.filter { $0.status == .suggested } }
    private var open: [ActionItem] { actions.filter { $0.status == .open } }
    private var done: [ActionItem] { actions.filter { $0.status == .done } }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if suggested.isEmpty && open.isEmpty && done.isEmpty {
                    ContentUnavailableView(
                        "No actions yet",
                        systemImage: "checklist",
                        description: Text("Actions from your meetings will appear here so nothing gets forgotten.")
                    )
                } else {
                    List {
                        if !suggested.isEmpty {
                            Section {
                                ForEach(suggested) { row($0) }
                            } header: {
                                Label("To review", systemImage: "sparkles")
                            } footer: {
                                Text("Suggested by AI from your transcripts. Accept the ones that are right.")
                            }
                        }
                        if !open.isEmpty {
                            Section("Open") {
                                ForEach(open) { row($0) }
                            }
                        }
                        if !done.isEmpty {
                            Section {
                                DisclosureGroup("Done (\(done.count))", isExpanded: $showDone) {
                                    ForEach(done.prefix(50)) { row($0) }
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Actions")
            .navigationDestination(for: Meeting.self) { MeetingDetailView(meeting: $0) }
        }
    }

    private func row(_ action: ActionItem) -> some View {
        ActionRow(action: action, showsMeeting: true)
            .swipeActions(edge: .trailing) {
                if let meeting = action.meeting {
                    Button {
                        path.append(meeting)
                    } label: {
                        Label("Meeting", systemImage: "waveform")
                    }
                    .tint(.indigo)
                }
            }
    }
}
