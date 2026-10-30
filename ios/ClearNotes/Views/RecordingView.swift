import SwiftUI
import UIKit

/// Full-screen live capture: timer, level meter, live transcript and the user's own notes.
struct RecordingView: View {
    enum Pane: String, CaseIterable {
        case transcript = "Live transcript"
        case notes = "My notes"
    }

    var onFinish: (RecordingResult, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKeys.requireOnDevice) private var requireOnDevice = true
    @State private var recorder = MeetingRecorder()
    @State private var notes = ""
    @State private var pane: Pane = .transcript
    @State private var errorMessage: String?
    @State private var confirmDiscard = false
    @State private var isFinishing = false
    @FocusState private var notesFocused: Bool

    var body: some View {
        VStack(spacing: 18) {
            header
            if let errorMessage {
                errorView(errorMessage)
            } else {
                timer
                LevelMeter(levels: recorder.levels, isActive: recorder.state == .recording)
                Picker("View", selection: $pane) {
                    ForEach(Pane.allCases, id: \.self) { Text($0.rawValue) }
                }
                .pickerStyle(.segmented)

                Group {
                    switch pane {
                    case .transcript: transcript
                    case .notes: notesEditor
                    }
                }
                .frame(maxHeight: .infinity)

                controls
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
        .background(Theme.canvas.ignoresSafeArea())
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
            Button {
                if recorder.state == .idle {
                    dismiss()
                } else {
                    confirmDiscard = true
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")

            Spacer()
            statusPill
            Spacer()
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.top, 8)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle.fill")
                .font(.system(size: 9))
                .foregroundStyle(recorder.state == .recording ? Theme.record : Color.secondary)
                .symbolEffect(.pulse, isActive: recorder.state == .recording)
            Text(statusText)
                .font(.subheadline.weight(.medium))
            if recorder.isOnDevice {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Transcribed on this iPhone")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.card, in: Capsule())
    }

    private var statusText: String {
        switch recorder.state {
        case .idle: isFinishing ? "Saving…" : "Starting…"
        case .recording: recorder.isOnDevice ? "Recording · On-device" : "Recording"
        case .paused: "Paused"
        case .stopping: "Saving…"
        }
    }

    private var timer: some View {
        Text(recorder.elapsed.clockString)
            .font(.system(size: 60, weight: .light, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
            .padding(.top, 4)
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if recorder.segments.isEmpty && recorder.liveText.isEmpty {
                        Text("Start talking. Your words will appear here.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 40)
                    }
                    ForEach(recorder.segments) { segment in
                        TranscriptLine(time: segment.start, text: segment.text)
                    }
                    if !recorder.liveText.isEmpty {
                        TranscriptLine(time: nil, text: recorder.liveText, isLive: true)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(16)
            }
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .onChange(of: recorder.liveText) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: recorder.segments.count) {
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    private var notesEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("Jot down what matters. AI uses your notes to decide what to focus on.")
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $notes)
                    .focused($notesFocused)
                    .scrollContentBackground(.hidden)
            }
            HStack(spacing: 8) {
                quickInsert("Action", symbol: "checkmark.circle", prefix: "Action: ")
                quickInsert("Decision", symbol: "signpost.right", prefix: "Decision: ")
                Spacer()
                if notesFocused {
                    Button("Done") { notesFocused = false }
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private var controls: some View {
        HStack(spacing: 20) {
            Button {
                togglePause()
            } label: {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(Theme.card, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(recorder.state != .recording && recorder.state != .paused)
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
                .frame(height: 64)
                .background(Theme.record, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(recorder.state != .recording && recorder.state != .paused)
        }
        .sensoryFeedback(.impact, trigger: recorder.state)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.slash")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(message)
                .multilineTextAlignment(.center)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .buttonStyle(.bordered)
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
                .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: - Actions

    private func start() async {
        guard await MeetingRecorder.requestPermissions() else {
            errorMessage = RecorderError.permissionDenied.errorDescription
            return
        }
        do {
            try recorder.start(requireOnDevice: requireOnDevice)
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
        onFinish(result, notes)
        dismiss()
    }
}

private struct TranscriptLine: View {
    var time: TimeInterval?
    var text: String
    var isLive = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(time?.clockString ?? "now")
                .font(.caption.monospacedDigit())
                .foregroundStyle(isLive ? AnyShapeStyle(Theme.record) : AnyShapeStyle(.secondary))
                .frame(width: 44, alignment: .leading)
            Text(text)
                .foregroundStyle(isLive ? .secondary : .primary)
        }
    }
}
