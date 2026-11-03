import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct ClearNotesLiveActivities: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivity()
    }
}

/// The recording on the Lock Screen and in the Dynamic Island: a timer, Pause or Resume, and
/// Mark action / Mark decision. Taps are handled by the app, which the recording keeps running.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            LockScreenRecordingView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    StatusLabel(state: context.state)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    RecordingTimer(state: context.state)
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 110, alignment: .trailing)
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        if let line = context.state.note ?? context.state.marksText {
                            Text(line)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        ControlRow(state: context.state)
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "waveform")
                    .foregroundStyle(context.state.isPaused ? Color.orange : RecordingColors.record)
            } compactTrailing: {
                RecordingTimer(state: context.state)
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 52, alignment: .trailing)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "waveform")
                    .foregroundStyle(context.state.isPaused ? Color.orange : RecordingColors.record)
            }
        }
    }
}

enum RecordingColors {
    static let record = Color(red: 1.0, green: 0.30, blue: 0.42)
    static let action = Color(red: 0.49, green: 0.42, blue: 1.0)
    static let decision = Color(red: 0.08, green: 0.72, blue: 0.65)
}

private struct LockScreenRecordingView: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    StatusLabel(state: state)
                    Text(state.note ?? state.marksText ?? "Clear Notes · on this iPhone")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                RecordingTimer(state: state)
                    .font(.system(size: 30, weight: .semibold).monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 150, alignment: .trailing)
            }
            ControlRow(state: state)
        }
        .padding(16)
        .foregroundStyle(.white)
    }
}

/// "● Recording" or "Paused".
private struct StatusLabel: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isPaused ? Color.orange : RecordingColors.record)
                .frame(width: 8, height: 8)
            Text(state.isPaused ? "Paused" : "Recording")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Counts up on its own, without updates from the app, and stops while paused.
private struct RecordingTimer: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        Text(
            timerInterval: state.timerStart...state.timerStart.addingTimeInterval(24 * 60 * 60),
            pauseTime: state.pausedAt,
            countsDown: false,
            showsHours: true
        )
        .foregroundStyle(.white)
    }
}

/// Pause or Resume, Mark action and Mark decision. Marking is off while paused.
private struct ControlRow: View {
    let state: RecordingActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 8) {
            if state.isPaused {
                Button(intent: ResumeRecordingIntent()) {
                    ControlLabel(title: "Resume", systemImage: "play.fill", tint: RecordingColors.record)
                }
                .buttonStyle(.plain)
            } else {
                Button(intent: PauseRecordingIntent()) {
                    ControlLabel(title: "Pause", systemImage: "pause.fill", tint: .white.opacity(0.18))
                }
                .buttonStyle(.plain)
            }
            Button(intent: MarkActionIntent()) {
                ControlLabel(title: "Action", systemImage: "checkmark.circle.fill", tint: RecordingColors.action)
            }
            .buttonStyle(.plain)
            .disabled(state.isPaused)
            .opacity(state.isPaused ? 0.4 : 1)
            Button(intent: MarkDecisionIntent()) {
                ControlLabel(title: "Decision", systemImage: "signpost.right.fill", tint: RecordingColors.decision)
            }
            .buttonStyle(.plain)
            .disabled(state.isPaused)
            .opacity(state.isPaused ? 0.4 : 1)
        }
    }
}

private struct ControlLabel: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(tint, in: Capsule())
    }
}
