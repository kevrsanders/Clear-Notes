import SwiftData
import SwiftUI

@main
struct ClearNotesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Meeting.self, ActionItem.self])
    }
}

struct ContentView: View {
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
    }
}
