import SwiftData
import SwiftUI
import UIKit

/// Full-screen live capture: a level orb, timer, live transcript and the user's own notes. Light or dark, like the rest of the app.
struct RecordingView: View {
    enum Pane: Hashable {
        case transcript, notes
    }

    /// The diary event this recording is for, chosen on the Record sheet.
    @State var calendarMeeting: CalendarMeeting? = nil
    /// What's being recorded: a meeting, a quick catch-up or a voice note.
    var kind: MeetingKind = .meeting
    var onFinish: (RecordingResult, String, CalendarMeeting?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(SettingsKeys.requireOnDevice) private var requireOnDevice = true
    @AppStorage(SettingsKeys.identifySpeakers) private var identifySpeakers = true
    @AppStorage(SettingsKeys.reduceEchoAndNoise) private var reduceEchoAndNoise = false
    @State private var recorder = MeetingRecorder()
    @State private var notes = ""
    @State private var pane: Pane = .transcript
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var isFinishing = false
    @State private var showLastTime = false
    /// How many people are in the meeting, if the user says. Optional: Auto works it out.
    @State private var peopleCount: Int?
    /// Who a catch-up is with, picked while recording (or later, on the meeting).
    @State private var person: String?
    @State private var addingPerson = false
    @State private var newPersonName = ""
    @AppStorage(SettingsKeys.myName) private var myName = ""
    @Query(filter: #Predicate<Meeting> { $0.deletedAt == nil }, sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
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
            Color.dynamic(light: 0xF4F4F8, dark: 0x07070B).ignoresSafeArea()
            Circle()
                .fill(Theme.recordGradient)
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                // Softer on a light background, where the same glow looks heavy.
                .opacity((isRecording ? 0.30 + Double(level) * 0.35 : 0.12) * (colorScheme == .dark ? 1 : 0.6))
                .offset(y: -180)
                .ignoresSafeArea()
                .animation(.easeOut(duration: 0.3), value: level)

            VStack(spacing: 18) {
                header
                if let calendarMeeting, errorMessage == nil {
                    linkedMeeting(calendarMeeting)
                } else if errorMessage == nil, kind == .catchUp {
                    catchUpBar
                } else if errorMessage == nil, kind == .voiceNote {
                    Label("Voice note · just me", systemImage: "mic.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.voiceNote)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Theme.voiceNote.opacity(0.14), in: Capsule())
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
                            .foregroundStyle(.primary)
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
        .task { await start() }
        .onAppear { ScreenAwake.hold() }
        .onDisappear { ScreenAwake.release() }
        .sheet(isPresented: $showLastTime) {
            if let previousMeeting {
                LastTimeView(meeting: previousMeeting)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(32)
            }
        }
        .alert("Who's this with?", isPresented: $addingPerson) {
            TextField("Name", text: $newPersonName)
                .textContentType(.name)
            Button("Done") {
                let name = newPersonName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { withAnimation(.snappy) { person = name } }
                newPersonName = ""
            }
            Button("Cancel", role: .cancel) { newPersonName = "" }
        }
        .confirmationDialog(kind == .voiceNote ? "Discard this voice note?" : "Discard this meeting?", isPresented: $confirmDiscard, titleVisibility: .visible) {
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
                    .fill(isRecording ? Theme.record : Color.primary.opacity(0.4))
                    .frame(width: 8, height: 8)
                    .shadow(color: Theme.record.opacity(isRecording ? 0.9 : 0), radius: 4)
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if recorder.isOnDevice {
                    Label("On-device", systemImage: "lock.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.primary.opacity(0.6))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .panel(in: Capsule())
            Spacer()
            if identifySpeakers && SpeakerSeparators.isSupported && kind != .voiceNote {
                peopleMenu
            } else {
                Color.clear.frame(width: 40, height: 40)
            }
        }
        .padding(.top, 8)
    }

    /// Optional and never in the way: how many people are speaking. A known number helps tell the
    /// voices apart afterwards; it doesn't change the words. Can be set any time before Stop.
    private var peopleMenu: some View {
        Menu {
            Section("How many people are speaking? It helps tell voices apart.") {
                Picker("People", selection: $peopleCount) {
                    Text("Auto").tag(Int?.none)
                    ForEach(2...8, id: \.self) { count in
                        Text("\(count) people").tag(Int?.some(count))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } label: {
            Group {
                if let peopleCount {
                    HStack(spacing: 2) {
                        Image(systemName: "person.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text("\(peopleCount)")
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                    }
                } else {
                    Image(systemName: "person.2")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .foregroundStyle(.primary)
            .frame(width: 40, height: 40)
            .panel(in: Circle())
        }
        .disabled(isFinishing)
        .accessibilityLabel("People in the meeting")
        .accessibilityValue(peopleCount.map { "\($0) people" } ?? "Auto")
        .accessibilityHint("Optional. Helps tell voices apart afterwards")
    }

    /// The last meeting in the linked meeting's series, if one was recorded.
    private var previousMeeting: Meeting? {
        guard let calendarMeeting else { return nil }
        return MeetingSeries.previous(
            seriesID: calendarMeeting.seriesID,
            title: calendarMeeting.title,
            before: calendarMeeting.start,
            in: meetings
        )
    }

    /// "Weekly check-in · 10:00–11:00 · 5 invited", with a button to unlink a wrong match.
    private func linkedMeeting(_ meeting: CalendarMeeting) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar")
                .foregroundStyle(Color.primary.opacity(0.6))
            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.title.isEmpty ? "Calendar event" : meeting.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text([meeting.timeRange, meeting.attendees.isEmpty ? nil : "\(meeting.attendees.count) invited"]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
            Spacer(minLength: 0)
            if previousMeeting != nil {
                Button {
                    showLastTime = true
                } label: {
                    Label("Last time", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.primary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the summary and actions from the last meeting in this series")
            }
            Button {
                withAnimation { calendarMeeting = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.primary.opacity(0.7))
                    .frame(width: 30, height: 30)
                    .background(Color.primary.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Not this meeting")
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
    }

    /// "Who's this with?": recent people one tap away, or someone else. Optional, and can be
    /// changed on the meeting afterwards.
    @ViewBuilder
    private var catchUpBar: some View {
        if let person {
            HStack(spacing: 10) {
                Image(systemName: MeetingKind.catchUp.systemImage)
                    .foregroundStyle(Theme.catchUp)
                Text("Catch-up with ").foregroundStyle(Color.primary.opacity(0.6))
                    + Text(person).fontWeight(.semibold).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { self.person = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.1), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Someone else")
            }
            .font(.subheadline)
            .lineLimit(1)
            .padding(.leading, 14)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("Quick catch-up · who's this with?", systemImage: MeetingKind.catchUp.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.catchUp)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(RecentPeople.list(from: meetings, me: myName), id: \.self) { name in
                            Button {
                                withAnimation(.snappy) { person = name }
                            } label: {
                                personChip(name)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            addingPerson = true
                        } label: {
                            personChip("Someone else", systemImage: "plus")
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollClipDisabled()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func personChip(_ name: String, systemImage: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
            }
            Text(name)
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(Color.primary.opacity(0.07), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08)))
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
                    if identifySpeakers && SpeakerSeparators.isSupported && kind != .voiceNote {
                        Label("Speakers are identified when you finish", systemImage: "person.2.wave.2")
                            .font(.footnote)
                            .foregroundStyle(Color.primary.opacity(0.45))
                            .padding(.top, 18)
                    }
                    if recorder.segments.isEmpty && recorder.liveText.isEmpty {
                        Text("Start talking. Your words will appear here.")
                            .font(.title3)
                            .foregroundStyle(Color.primary.opacity(0.4))
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
                        .foregroundStyle(Color.primary.opacity(0.35))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $notes)
                    .focused($notesFocused)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(.primary)
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
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }

    /// One tap, just after something is agreed, marks it. After the meeting the moments before
    /// each mark become an action or decision.
    private var markBar: some View {
        HStack(spacing: 10) {
            if kind == .voiceNote {
                // A voice note's actions are the user's own to-dos; there's nobody to agree with.
                markButton(.action, title: "Mark to-do", systemImage: "checkmark.circle.fill")
            } else {
                markButton(.action, title: "Mark action", systemImage: "checkmark.circle.fill")
                markButton(.decision, title: "Mark decision", systemImage: "signpost.right.fill")
            }
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
                        .background(Color.primary.opacity(0.2), in: Capsule())
                        .contentTransition(.numericText())
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .panel(in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isRecording)
        .opacity(isRecording ? 1 : 0.5)
        .accessibilityLabel(title)
        .accessibilityValue(count > 0 ? "\(count) marked" : "")
        .accessibilityHint(self.kind == .voiceNote ? "Tap just after saying something you need to do" : "Tap just after it's agreed")
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Button(action: togglePause) {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 60, height: 60)
                    .panel(in: Circle())
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
                .foregroundStyle(Color.primary.opacity(0.5))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
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
        // Two voices in a catch-up, unless the user says otherwise.
        if kind == .catchUp, peopleCount == nil {
            peopleCount = 2
        }
        guard await MeetingRecorder.requestPermissions() else {
            errorMessage = RecorderError.permissionDenied.errorDescription
            return
        }
        do {
            try await recorder.start(
                requireOnDevice: requireOnDevice,
                captureAudioForSpeakers: (identifySpeakers && SpeakerSeparators.isSupported && kind != .voiceNote)
                    || AudioRetention.current.keepsAudio,
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
        var result = await recorder.stop()
        result.expectedSpeakers = peopleCount
        result.kind = calendarMeeting == nil ? kind : .meeting
        result.person = kind == .catchUp ? person : nil
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
                .foregroundStyle(isLive ? AnyShapeStyle(Theme.record) : AnyShapeStyle(Color.primary.opacity(0.4)))
            Text(text)
                .font(.body)
                .foregroundStyle(isLive ? Color.primary.opacity(0.6) : Color.primary.opacity(0.92))
        }
    }
}
