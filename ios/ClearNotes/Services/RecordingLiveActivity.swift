import ActivityKit
import Foundation

/// Starts, updates and ends the recording's Lock Screen and Dynamic Island controls (see
/// `RecordingActivityAttributes`). The timer runs on its own; updates are only sent when the
/// recording is paused, resumed or marked.
final class RecordingLiveActivity {
    typealias State = RecordingActivityAttributes.ContentState

    private var activity: Activity<RecordingActivityAttributes>?
    private(set) var state: State?
    /// The activity of the recording in progress, which `endStale()` leaves alone.
    private static var currentID: String?

    func start(elapsed: TimeInterval = 0) {
        guard activity == nil else { return }
        let initial = State(timerStart: Date().addingTimeInterval(-elapsed))
        state = initial
        // Apple Watch shows it too, with Pause and Mark buttons, even with Live Activities off.
        PhoneRecordingMirror.publish(initial)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            let started = try Activity.request(
                attributes: RecordingActivityAttributes(),
                content: ActivityContent(state: initial, staleDate: nil)
            )
            activity = started
            state = initial
            Self.currentID = started.id
        } catch {
            // Live Activities can be turned off in Settings; recording carries on without them.
            activity = nil
        }
    }

    func update(_ change: (inout State) -> Void) {
        guard var next = state else { return }
        change(&next)
        state = next
        PhoneRecordingMirror.publish(next)
        guard let activity else { return }
        let content = ActivityContent(state: next, staleDate: nil)
        Task { await activity.update(content) }
    }

    func end() {
        state = nil
        PhoneRecordingMirror.publish(nil)
        guard let activity else { return }
        self.activity = nil
        if Self.currentID == activity.id { Self.currentID = nil }
        Task { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    /// Removes controls left on the Lock Screen by a recording that didn't finish, e.g. when the
    /// app was closed from the app switcher mid-meeting.
    static func endStale() {
        for activity in Activity<RecordingActivityAttributes>.activities where activity.id != currentID {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }

    /// What the state becomes when the recording is paused, resumed or marked. Kept separate so
    /// it can be tested without ActivityKit.
    static func paused(_ state: State, at date: Date = .now) -> State {
        var next = state
        next.pausedAt = date
        next.note = nil
        return next
    }

    static func resumed(_ state: State, elapsed: TimeInterval, at date: Date = .now) -> State {
        var next = state
        next.timerStart = date.addingTimeInterval(-elapsed)
        next.pausedAt = nil
        next.note = nil
        return next
    }

    static func marked(_ state: State, kind: MeetingMark.Kind, at time: TimeInterval) -> State {
        var next = state
        switch kind {
        case .action:
            next.actionMarks += 1
            next.note = "Action marked at \(time.clockString)"
        case .decision:
            next.decisionMarks += 1
            next.note = "Decision marked at \(time.clockString)"
        }
        return next
    }
}
