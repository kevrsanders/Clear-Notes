import SwiftUI

/// The start screen (a big Record button, voice note or catch-up), or the recording.
struct HomeView: View {
    @State private var recorder = WatchRecorder.shared
    @State private var sender = WatchSender.shared
    @State private var kind = WatchRecorder.shared.preferredKind
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if recorder.isRecording {
                RecordingScreen(recorder: recorder)
            } else if let phone = sender.phoneRecording {
                // The iPhone is recording: the watch is its remote.
                PhoneRemoteScreen(state: phone, sender: sender)
            } else {
                startScreen
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { sender.sendWaiting() }
        }
    }

    private var startScreen: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let offered = recorder.offered {
                    Button {
                        Task { await recorder.start(.meeting, reminder: offered) }
                    } label: {
                        Label(offered.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Record this meeting", systemImage: "calendar")
                            .lineLimit(2)
                    }
                    .tint(.red)
                }
                Button {
                    Task { await recorder.start(kind) }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(
                                colors: [Color(red: 1, green: 0.48, blue: 0.35), Color(red: 1, green: 0.24, blue: 0.44)],
                                startPoint: .topLeading, endPoint: .bottomTrailing
                            ))
                        Image(systemName: "mic.fill")
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 88, height: 88)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(kind == .catchUp ? "Record a catch-up" : "Record a voice note")

                HStack(spacing: 4) {
                    kindButton(.voiceNote, title: "Voice note")
                    kindButton(.catchUp, title: "Catch-up")
                }

                if let message = recorder.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                status
            }
            .padding(.horizontal, 4)
        }
    }

    private func kindButton(_ option: WatchRecordingInfo.Kind, title: String) -> some View {
        Button {
            kind = option
            recorder.preferredKind = option
        } label: {
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
        }
        .tint(kindTint(option))
        .accessibilityAddTraits(kind == option ? .isSelected : [])
    }

    private func kindTint(_ option: WatchRecordingInfo.Kind) -> Color {
        guard kind == option else { return Color.gray }
        return option == .voiceNote ? Color.orange : Color.cyan
    }

    @ViewBuilder
    private var status: some View {
        if sender.waiting > 0 {
            Label(sender.waiting == 1 ? "1 waiting for iPhone" : "\(sender.waiting) waiting for iPhone", systemImage: "iphone.radiowaves.left.and.right")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if recorder.lastFinished != nil {
            Label("Sent to iPhone", systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        } else {
            Text("Notes are written on your iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

/// Timer, level, mark and stop while recording.
private struct RecordingScreen: View {
    let recorder: WatchRecorder

    private var title: String {
        switch recorder.kind {
        case .voiceNote: "Voice note"
        case .catchUp: "Catch-up"
        case .meeting: recorder.reminder?.title.flatMap { $0.isEmpty ? nil : $0 } ?? "Diary meeting"
        }
    }

    private var tint: Color {
        switch recorder.kind {
        case .voiceNote: .orange
        case .catchUp: .cyan
        case .meeting: .blue
        }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                VStack(spacing: 6) {
                    Text(clock(recorder.elapsed))
                        .font(.system(size: 32, weight: .light).monospacedDigit())
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.red.opacity(0.25))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(Color.red)
                                    .frame(width: max(6, proxy.size.width * recorder.level()))
                            }
                    }
                    .frame(height: 6)
                    .padding(.horizontal, 16)
                }
            }
            HStack(spacing: 6) {
                Button {
                    recorder.mark()
                } label: {
                    Label(recorder.kind == .voiceNote ? "To-do" : "Action", systemImage: "checkmark.circle")
                        .font(.footnote.weight(.semibold))
                }
                .tint(.teal)
                Button {
                    recorder.stop()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.footnote.weight(.semibold))
                }
                .tint(.red)
            }
            if !recorder.marks.isEmpty {
                Text(recorder.marks.count == 1 ? "1 marked" : "\(recorder.marks.count) marked")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

}

/// "04:12" or "1:04:12".
private func clock(_ time: TimeInterval) -> String {
    let seconds = Int(time)
    let hours = seconds / 3_600
    let minutes = (seconds % 3_600) / 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, seconds % 60)
        : String(format: "%02d:%02d", minutes, seconds % 60)
}

/// While the iPhone records a meeting (it hears a room far better than a watch): its timer, Mark
/// action and decision, and Pause or Resume. A tap on the wrist confirms each one.
private struct PhoneRemoteScreen: View {
    let state: PhoneRecordingState
    let sender: WatchSender

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isPaused ? Color.gray : Color.red)
                        .frame(width: 6, height: 6)
                    Text(state.isPaused ? "Paused on iPhone" : "Recording on iPhone")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(state.isPaused ? Color.secondary : Color.red)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(state.elapsed(at: context.date)))
                        .font(.system(size: 30, weight: .light).monospacedDigit())
                }
                if let confirmation = sender.confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else if let error = sender.remoteError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else if let marks = state.marksText {
                    Text(marks)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Button {
                        sender.send(PhoneRemote.markAction, confirm: "Action marked")
                    } label: {
                        Label("Action", systemImage: "checkmark.circle")
                            .font(.footnote.weight(.semibold))
                    }
                    .tint(.teal)
                    Button {
                        sender.send(PhoneRemote.markDecision, confirm: "Decision marked")
                    } label: {
                        Label("Decision", systemImage: "signpost.right")
                            .font(.footnote.weight(.semibold))
                    }
                    .tint(.green)
                }
                .disabled(state.isPaused)
                Button {
                    if state.isPaused {
                        sender.send(PhoneRemote.resume, confirm: "Recording again")
                    } else {
                        sender.send(PhoneRemote.pause, confirm: "Paused")
                    }
                } label: {
                    Label(state.isPaused ? "Resume" : "Pause", systemImage: state.isPaused ? "play.fill" : "pause.fill")
                        .font(.footnote.weight(.semibold))
                }
            }
        }
        // The confirmation shows for a moment, then the marks count comes back.
        .task(id: sender.confirmation) {
            guard sender.confirmation != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            sender.clearConfirmation()
        }
    }
}
