import SwiftUI
import UserNotifications

/// Clear Notes on Apple Watch: records voice notes, catch-ups and diary meetings on the watch and
/// sends them to the iPhone, which transcribes them and writes the notes there.
@main
struct ClearNotesWatchApp: App {
    init() {
        // Recordings waiting on the watch go to the iPhone whenever it's in reach.
        WatchSender.shared.activate()
        ReminderActions.shared.register()
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
                // The watch-face button opens Clear Notes and starts recording straight away.
                .onOpenURL { url in
                    guard url.host == "record" else { return }
                    Task { await WatchRecorder.shared.startFromWatchFace() }
                }
        }
    }
}

/// Meeting reminders from the iPhone show on the watch. Record starts recording that meeting on
/// the watch; tapping the reminder itself offers it at the top of the start screen.
final class ReminderActions: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderActions()

    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let record = UNNotificationAction(
            identifier: MeetingReminderNotification.recordAction,
            title: "Record on watch",
            options: [.foreground]
        )
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: MeetingReminderNotification.category,
                actions: [record],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let content = response.notification.request.content
        if content.categoryIdentifier == MeetingReminderNotification.category,
           response.actionIdentifier != UNNotificationDismissActionIdentifier {
            let eventID = content.userInfo[MeetingReminderNotification.eventIDKey] as? String
            let title = content.userInfo[MeetingReminderNotification.eventTitleKey] as? String
            let recordNow = response.actionIdentifier == MeetingReminderNotification.recordAction
            Task { @MainActor in
                let reminder = WatchRecorder.Reminder(eventID: eventID, title: title)
                if recordNow {
                    await WatchRecorder.shared.start(.meeting, reminder: reminder)
                } else {
                    WatchRecorder.shared.offered = reminder
                }
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
