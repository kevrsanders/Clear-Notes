import SwiftData
import SwiftUI
import UIKit

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
    @State private var tab = 0
    /// A shared meeting file someone opened in Clear Notes.
    @State private var importRequest: ImportRequest?

    var body: some View {
        // Actions live inside each meeting, so there's no separate Actions tab.
        TabView(selection: $tab) {
            MeetingsListView()
                .tabItem { Label("Meetings", systemImage: "waveform") }
                .tag(0)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(1)
        }
        .tint(Theme.brand)
        .task {
            RecordingLiveActivity.endStale()
            MeetingSharing.clearSharedFiles()
            await MeetingProcessor.resumeUnfinished(in: context)
        }
        .onOpenURL { url in
            guard url.isFileURL else { return }
            importRequest = ImportRequest(url: url)
        }
        .sheet(item: $importRequest) { request in
            ImportMeetingView(url: request.url) { meeting in
                tab = 0
                let id = meeting.persistentModelID
                // After the sheet closes and the meeting list has updated.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    NotificationCenter.default.post(name: .openMeeting, object: id)
                }
            }
        }
        // The recording can only be read while the iPhone is unlocked, so processing that was
        // waiting carries on as soon as it is.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            Task { await MeetingProcessor.resumeProcessing(in: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Notes paused in the background (Apple Intelligence limits background apps) carry on.
            if phase == .active {
                Task { await MeetingProcessor.resumeProcessing(in: context) }
            }
        }
    }
}
