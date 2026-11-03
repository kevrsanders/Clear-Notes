import SwiftUI
import UIKit

/// Full-screen live capture, always dark: a level orb, timer, live transcript and the user's own notes.
struct RecordingView: View {
    enum Pane: Hashable {
        case transcript, notes
    }

    /// The calendar event this recording is for. Found automatically when not given.
    @State var calendarMeeting: CalendarMeeting? = nil
    var onFinish: (RecordingResult, String, CalendarMeeting?) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.requireOnDevice) private var requireOnDevice = true
    @AppStorage(SettingsKeys.identifySpeakers) private var identifySpeakers = true
    @AppStorage(SettingsKeys.reduceEchoAndNoise) private var reduceEchoAndNoise = false
    @State private var recorder = MeetingRecorder()
    @State private var notes = ""
    @State private var pane: Pane = .transcript
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var isFinishing = false
    @FocusState private var notesFocused: Bool

    private var isRecording: Bool { recorder.state == .recording }
    private var canControl: Bool { recorder.state == .recording || recorder.state == .paused }

    /// Average of the latest levels, so the orb moves smoothly.
    private var level: CGFloat {
        let recent = recorder.levels.suffix(3)
        return CGFloat(recent.reduce(0, +) / Float(max(recent.count, 1)))
    }

    var body: some View {
        ZStack {
            Color(hex: 0x07070B).ignoresSafeArea()
            Circle()
                .fill(Theme.recordGradient)
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .opacity(isRecording ? 0.30 + Double(level) * 0.35 : 0.12)
                .offset(y: -180)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.3), value: level)

            VStack(spacing: 18) {
                header
                if let calendarMeeting, errorMessage == nil {
                    linkedMeeting(calendarMeeting)
                }
                if let errorMessage {
                    errorView(errorMessage)
                } else {
                    VStack(spacing: 4) {
                        LevelOrb(level: level, isActive: isRecording)
                        Text(recorder.elapsed.clockString)
                            .font(.system(size: 60, weight: .thin))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(.white)
                    }
                    PillTabs<Pane>(
                        items: [.init(value: .transcript, title: "Transcript"), .init(value: .notes, title: "My notes")],
                        selection: $pane
                    )
                    Group {
                        switch pane {
                        case .transcript: transcript
                        case .notes: notesEditor
                        }
                    }
                    .frame(maxHeight: .infinity)
                    markBar
                    controls
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 8)
        }
        .preferredColorScheme(.dark)
        .task { await start() }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .confirmationDialog("Discard this meeting?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) {
                recorder.discard()
                dismiss()
            }
        } message: {
            Text("The transcript and your notes will be deleted.")
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            GlassCircleButton(systemName: "xmark", accessibilityLabel: "Close") {
                if recorder.state == .idle {
                    dismiss()
                } else {
                    confirmDiscard = true
                }
            }
            Spacer()
            HStack(spacing: 8) {
                Circle()
                    .fill(isRecording ? Theme.record : Color.white.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.record.opacity(isRecording ? 0.9 : 0), radius: 4)
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                if recorder.isOnDevice {
                    Label("On-device", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .glass(in: Capsule())
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.top, 8)
    }

    /// "Weekly check-in · 10:00–11:00 · 5 invited", with a button to unlink a wrong match.
    private func linkedMeeting(_ meeting: CalendarMeeting) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(.white.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title.isEmpty ? "Calendar event" : meeting.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text([meeting.timeRange, meeting.attendees.isEmpty ? nil : "\(meeting.attendees.count) invited"]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer(minLength: 0)
            Button {
                withAnimation { calendarMeeting = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not this meeting")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
    }

    private var statusText: String {
        switch recorder.state {
        case .idle: isFinishing ? "Saving…" : "Starting…"
        case .recording: "REC"
        case .paused: "Paused"
        case .stopping: "Saving…"
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if identifySpeakers && SpeakerSeparators.isSupported {
                        Label("Speakers are identified when you finish", systemImage: "person.2.wave.2")
                            .font(.footnote)
                            .foregroundStyle(.white.opacity(0.45))
                            .padding(.top, 18)
                    }
                    if recorder.segments.isEmpty && recorder.liveText.isEmpty {
                        Text("Start talking. Your words will appear here.")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.4))
                            .padding(.top, 8)
                    }
                    ForEach(recorder.segments) { segment in
                        LiveLine(time: segment.start, text: segment.text)
                    }
                    if !recorder.liveText.isEmpty {
                        LiveLine(time: nil, text: recorder.liveText, isLive: true)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            }
            .mask(
                LinearGradient(
                    stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1), .init(color: .black, location: 1)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .onChange(of: recorder.liveText) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: recorder.segments.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Jot down what matters. The AI uses your notes to decide what to focus on.")
                        .foregroundStyle(.white.opacity(0.35))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $notes)
                    .focused($notesFocused)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.white)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    quickInsert("Action", symbol: "checkmark.circle", prefix: "Action: ")
                    quickInsert("Decision", symbol: "signpost.right", prefix: "Decision: ")
                    quickInsert("Moment", symbol: "bookmark", prefix: "Moment: ")
                    if notesFocused {
                        Button("Done") { notesFocused = false }
                            .buttonStyle(SecondaryButtonStyle(compact: true))
                    }
                }
            }
        }
        .padding(14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }

    /// One tap, just after something is agreed, marks it. After the meeting the moments before
    /// each mark become an action or decision.
    private var markBar: some View {
        HStack(spacing: 10) {
            markButton(.action, title: "Mark action", systemImage: "checkmark.circle.fill")
            markButton(.decision, title: "Mark decision", systemImage: "signpost.right.fill")
        }
        .sensoryFeedback(.success, trigger: recorder.marks.count)
    }

    private func markButton(_ kind: MeetingMark.Kind, title: String, systemImage: String) -> some View {
        let count = recorder.marks.filter { $0.kind == kind }.count
        return Button {
            recorder.mark(kind)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.white.opacity(0.2), in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .glass(in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isRecording)
        .opacity(isRecording ? 1 : 0.5)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count) marked" : "")
        .accessibilityHint("Tap just after it's agreed")
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(action: togglePause) {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 60, height: 60)
                    .glass(in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canControl)
            .accessibilityLabel(recorder.state == .paused ? "Resume" : "Pause")

            Button {
                Task { await finish() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "stop.fill")
                    Text("Finish")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(Theme.recordGradient, in: Capsule())
                .shadow(color: Theme.record.opacity(0.45), radius: 16, y: 6)
            }
            .buttonStyle(.plain)
            .disabled(!canControl)
            .opacity(canControl ? 1 : 0.5)
        }
        .sensoryFeedback(.impact, trigger: recorder.state)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 40))
                .foregroundStyle(.white.opacity(0.5))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(PrimaryButtonStyle())
            }
            Spacer()
        }
    }

    private func quickInsert(_ title: String, symbol: String, prefix: String) -> some View {
        Button {
            let stamp = "[\(recorder.elapsed.clockString)] "
            if !notes.isEmpty && !notes.hasSuffix("\n") { notes += "\n" }
            notes += prefix + stamp
            pane = .notes
            notesFocused = true
        } label: {
            Label(title, systemImage: symbol)
        }
        .buttonStyle(SecondaryButtonStyle(compact: true))
    }

    // MARK: - Actions

    private func start() async {
        if calendarMeeting == nil {
            calendarMeeting = CalendarReader.shared.currentMeeting()
        }
        guard await MeetingRecorder.requestPermissions() else {
            errorMessage = RecorderError.permissionDenied.errorDescription
            return
        }
        do {
            try await recorder.start(
                requireOnDevice: requireOnDevice,
                captureAudioForSpeakers: (identifySpeakers && SpeakerSeparators.isSupported) || AudioRetention.current.keepsAudio,
                reduceEchoAndNoise: reduceEchoAndNoise
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePause() {
        if recorder.state == .paused {
            do { try recorder.resume() } catch { errorMessage = error.localizedDescription }
        } else {
            recorder.pause()
        }
    }

    private func finish() async {
        isFinishing = true
        notesFocused = false
        let result = await recorder.stop()
        onFinish(result, notes, calendarMeeting)
        dismiss()
    }
}

/// Glowing orb that grows with the microphone level.
private struct LevelOrb: View {
    var level: CGFloat
    var isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.recordGradient)
                .opacity(0.14)
                .scaleEffect(isActive ? 0.85 + level * 0.3 : 0.8)
            Circle()
                .fill(Theme.recordGradient)
                .opacity(0.3)
                .scaleEffect(isActive ? 0.66 + level * 0.2 : 0.62)
            Circle()
                .fill(Theme.recordGradient)
                .frame(width: 84, height: 84)
                .shadow(color: Theme.record.opacity(isActive ? 0.7 : 0.2), radius: 22)
            Image(systemName: isActive ? "waveform" : "pause.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: isActive)
        }
        .frame(width: 150, height: 150)
        .saturation(isActive ? 1 : 0.3)
        .animation(.easeOut(duration: 0.15), value: level)
        .animation(.easeInOut(duration: 0.3), value: isActive)
        .accessibilityHidden(true)
    }
}

private struct LiveLine: View {
    var time: TimeInterval?
    var text: String
    var isLive = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time?.clockString ?? "Now")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(isLive ? AnyShapeStyle(Theme.record) : AnyShapeStyle(Color.white.opacity(0.4)))
            Text(text)
                .font(.body)
                .foregroundStyle(isLive ? Color.white.opacity(0.6) : Color.white.opacity(0.92))
        }
    }
}
