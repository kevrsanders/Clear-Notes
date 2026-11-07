import Foundation
import UserNotifications

extension Notification.Name {
    /// A meeting reminder was tapped on the iPhone: record that diary meeting.
    static let recordDiaryEvent = Notification.Name("ClearNotes.recordDiaryEvent")
}

/// A reminder as each meeting in the diary starts, with Record. When the iPhone is locked or put
/// away, iOS shows it on Apple Watch, where Record starts recording on the watch. On the iPhone,
/// Record opens Clear Notes to record the meeting there.
enum MeetingReminders {
    struct Plan: Equatable {
        var identifier: String
        var fireDate: Date
        var title: String
        var body: String
        var eventID: String
        var eventTitle: String
    }

    /// Settings → Calendar → Remind me when a meeting starts (off by default).
    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.meetingReminders)
    }

    /// Whether the reminder names the meeting. Off by default, since anyone who can see the
    /// Lock Screen or the watch can read it.
    static var showsTitles: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.reminderShowsTitle)
    }

    /// The reminders to schedule: meetings with other people invited that haven't started and
    /// haven't been recorded, soonest first. At most 30 (iOS keeps up to 64 waiting).
    @MainActor
    static func plan(events: [CalendarMeeting], meetings: [Meeting], now: Date, showTitles: Bool) -> [Plan] {
        var seen = Set<String>()
        return events
            .filter { CalendarMeetingPicker.usable($0) && $0.hasPeople && $0.start > now.addingTimeInterval(5) }
            .filter { event in !meetings.contains { DiaryDay.isRecording($0, of: event) } }
            .filter { seen.insert($0.id).inserted }
            .sorted { $0.start < $1.start }
            .prefix(30)
            .map { event in
                let name = event.title.isEmpty ? "A meeting" : event.title
                let invited = event.attendees.isEmpty ? "" : " · \(event.attendees.count) invited"
                return Plan(
                    identifier: MeetingReminderNotification.identifierPrefix + event.id,
                    fireDate: event.start,
                    title: showTitles ? "\(name) is starting" : "A meeting is starting",
                    body: event.timeRange + invited,
                    eventID: event.id,
                    eventTitle: showTitles ? event.title : ""
                )
            }
    }

    /// What was scheduled last, so the same reminders aren't scheduled again every minute.
    @MainActor private static var scheduled: [Plan]?

    /// Schedules reminders for the given diary events, replacing earlier ones.
    @MainActor
    static func update(events: [CalendarMeeting], meetings: [Meeting], now: Date = .now) async {
        let center = UNUserNotificationCenter.current()
        let wanted = isEnabled ? plan(events: events, meetings: meetings, now: now, showTitles: showsTitles) : []
        guard wanted != scheduled else { return }
        scheduled = wanted

        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(MeetingReminderNotification.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
        guard !wanted.isEmpty else { return }
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { return }

        for plan in wanted {
            let content = UNMutableNotificationContent()
            content.title = plan.title
            content.body = plan.body
            content.sound = .default
            content.categoryIdentifier = MeetingReminderNotification.category
            content.userInfo = [
                MeetingReminderNotification.eventIDKey: plan.eventID,
                MeetingReminderNotification.eventTitleKey: plan.eventTitle,
            ]
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, plan.fireDate.timeIntervalSince(now)), repeats: false)
            try? await center.add(UNNotificationRequest(identifier: plan.identifier, content: content, trigger: trigger))
        }
    }

    /// Asks to show notifications, when the user turns reminders on.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }
}

/// Handles a meeting reminder tapped on the iPhone: Clear Notes opens to record that meeting.
final class ReminderHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ReminderHandler()

    /// The diary event whose reminder was tapped, until the meetings screen picks it up (it may
    /// not exist yet when the tap launched Clear Notes).
    @MainActor static var pendingEventID: String?

    func register() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let record = UNNotificationAction(
            identifier: MeetingReminderNotification.recordAction,
            title: "Record",
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
           response.actionIdentifier != UNNotificationDismissActionIdentifier,
           let eventID = content.userInfo[MeetingReminderNotification.eventIDKey] as? String {
            Task { @MainActor in
                ReminderHandler.pendingEventID = eventID
                NotificationCenter.default.post(name: .recordDiaryEvent, object: eventID)
            }
        }
        completionHandler()
    }

    /// Shown as a banner even with Clear Notes open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
