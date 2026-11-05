import UIKit

/// Keeps the screen on while any screen that needs it is showing (recording, or a meeting being
/// processed). Counted, so one screen closing as another opens doesn't let the iPhone auto-lock.
@MainActor
enum ScreenAwake {
    private static var holders = 0

    static func hold() {
        holders += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func release() {
        holders = max(0, holders - 1)
        UIApplication.shared.isIdleTimerDisabled = holders > 0
    }
}
