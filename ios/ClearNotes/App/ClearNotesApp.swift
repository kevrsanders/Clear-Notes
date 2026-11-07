import SwiftData
import SwiftUI
import UIKit

@main
struct ClearNotesApp: App {
    init() {
        // Recordings from Apple Watch, and taps on meeting reminders, can arrive at any time.
        WatchLink.shared.activate()
        ReminderHandler.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Meeting.self, ActionItem.self, VoiceProfile.self])
    }
}

extension Notification.Name {
    /// Posted by the Record tab; the Meetings screen starts a new recording.
    static let startRecording = Notification.Name("ClearNotes.startRecording")
}

struct ContentView: View {
    private static let recordTab = 2
    /// Red, so Record stands out from the other tabs (tab icons are otherwise tinted alike).
    private static let recordIcon: UIImage = {
        let configuration = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let image = UIImage(systemName: "record.circle.fill", withConfiguration: configuration) ?? UIImage()
        return image.withTintColor(UIColor(Theme.record), renderingMode: .alwaysOriginal)
    }()

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0
    @AppStorage(SettingsKeys.appearance) private var appearance = AppAppearance.system.rawValue
    /// A shared meeting file someone opened in Clear Notes.
    @State private var importRequest: ImportRequest?

    var body: some View {
        // Actions live inside each meeting, so there's no separate Actions tab.
        // Record sits in the middle of the tab bar. It isn't a real tab: choosing it starts a
        // recording from the Meetings screen and leaves the current tab selected.
        TabView(selection: Binding(get: { tab }, set: { choice in
            if choice == Self.recordTab {
                startRecording()
            } else {
                tab = choice
            }
        })) {
            MeetingsListView()
                .tabItem { Label("Meetings", systemImage: "waveform") }
                .tag(0)
            Color.clear
                .tabItem {
                    Label {
                        Text("Record")
                    } icon: {
                        Image(uiImage: Self.recordIcon)
                    }
                }
                .tag(Self.recordTab)
                .accessibilityHint("Starts recording a meeting")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(1)
        }
        .tint(Theme.brand)
        .task {
            RecordingLiveActivity.endStale()
            MeetingSharing.clearSharedFiles()
            RecentlyDeleted.purgeExpired(in: context)
            WatchInbox.importAll(into: context)
            MinutesJobs.shared.resumePaused(in: context)
            await MeetingProcessor.resumeUnfinished(in: context)
        }
        .onChange(of: appearance, initial: true) { _, value in
            AppAppearance.apply(value)
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
        // A recording from Apple Watch arrived: it becomes a meeting and is transcribed here.
        .onReceive(NotificationCenter.default.publisher(for: .watchRecordingArrived)) { _ in
            WatchInbox.importAll(into: context)
        }
        // A meeting reminder was tapped: the Meetings screen opens the recorder.
        .onReceive(NotificationCenter.default.publisher(for: .recordDiaryEvent)) { _ in
            tab = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.protectedDataDidBecomeAvailableNotification)) { _ in
            Task { await MeetingProcessor.resumeProcessing(in: context) }
        }
        .onChange(of: scenePhase) { _, phase in
            // Notes and minutes paused in the background (Apple Intelligence limits background
            // apps) carry on from where they stopped.
            if phase == .active {
                WatchInbox.importAll(into: context)
                MinutesJobs.shared.resumePaused(in: context)
                Task { await MeetingProcessor.resumeProcessing(in: context) }
            }
        }
    }

    private func startRecording() {
        tab = 0
        // Once the Meetings screen is showing, so it can present the recorder.
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .startRecording, object: nil)
        }
    }
}
