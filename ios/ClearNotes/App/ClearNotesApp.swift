import SwiftData
import SwiftUI

@main
struct ClearNotesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Meeting.self, ActionItem.self, VoiceProfile.self])
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var actions: [ActionItem]

    private var actionBadge: Int {
        actions.filter { $0.status == .suggested || $0.status == .open }.count
    }

    var body: some View {
        TabView {
            MeetingsListView()
                .tabItem { Label("Meetings", systemImage: "waveform") }
            ActionsView()
                .tabItem { Label("Actions", systemImage: "checklist") }
                .badge(actionBadge)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.brand)
        .task { await MeetingProcessor.resumeUnfinished(in: context) }
        .onChange(of: scenePhase) { _, phase in
            // Notes paused in the background (Apple Intelligence limits background apps) carry on.
            if phase == .active {
                Task { await MeetingProcessor.resumeProcessing(in: context) }
            }
        }
    }
}
