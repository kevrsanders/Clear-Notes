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

    var body: some View {
        // Actions live inside each meeting, so there's no separate Actions tab.
        TabView {
            MeetingsListView()
                .tabItem { Label("Meetings", systemImage: "waveform") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .tint(Theme.brand)
        .task {
            RecordingLiveActivity.endStale()
            await MeetingProcessor.resumeUnfinished(in: context)
        }
        .onChange(of: scenePhase) { _, phase in
            // Notes paused in the background (Apple Intelligence limits background apps) carry on.
            if phase == .active {
                Task { await MeetingProcessor.resumeProcessing(in: context) }
            }
        }
    }
}
