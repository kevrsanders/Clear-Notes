import ActivityKit
import AppIntents
import Foundation

/// The recording on the Lock Screen and in the Dynamic Island. Shared by the app, which starts and
/// updates it, and the Lock Screen extension, which draws it.
///
/// It deliberately shows no meeting title or names: the Lock Screen can be seen by anyone nearby.
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// When the timer would have started without pauses, so it shows recording time only.
        var timerStart: Date
        /// Set while paused: the timer stops at this moment.
        var pausedAt: Date?
        var actionMarks: Int = 0
        var decisionMarks: Int = 0
        /// A short line such as "Action marked at 12:04" or "Open Clear Notes to resume".
        var note: String?

        var isPaused: Bool { pausedAt != nil }

        /// "2 actions · 1 decision marked", or nil before anything is marked.
        var marksText: String? {
            var parts: [String] = []
            if actionMarks > 0 { parts.append("\(actionMarks) action\(actionMarks == 1 ? "" : "s")") }
            if decisionMarks > 0 { parts.append("\(decisionMarks) decision\(decisionMarks == 1 ? "" : "s")") }
            return parts.isEmpty ? nil : parts.joined(separator: " · ") + " marked"
        }
    }
}

/// What the Lock Screen buttons ask the recording to do.
enum RecordingCommand: String, Sendable {
    case pause, resume, markAction, markDecision
}

/// Passes Lock Screen button taps to the recording. The buttons' intents run in the app's own
/// process (the recording keeps it running), where the recorder sets `handler`. In the Lock Screen
/// extension it stays nil, because the extension only draws the buttons.
enum RecordingControls {
    static var handler: ((RecordingCommand) -> Void)?

    @MainActor
    static func send(_ command: RecordingCommand) {
        handler?(command)
    }
}

struct PauseRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause recording"

    func perform() async throws -> some IntentResult {
        await RecordingControls.send(.pause)
        return .result()
    }
}

struct ResumeRecordingIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume recording"

    func perform() async throws -> some IntentResult {
        await RecordingControls.send(.resume)
        return .result()
    }
}

struct MarkActionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark action"

    func perform() async throws -> some IntentResult {
        await RecordingControls.send(.markAction)
        return .result()
    }
}

struct MarkDecisionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mark decision"

    func perform() async throws -> some IntentResult {
        await RecordingControls.send(.markDecision)
        return .result()
    }
}
