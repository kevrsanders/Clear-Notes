import Speech
import SwiftUI

enum SettingsKeys {
    static let showConsentReminder = "showConsentReminder"
    static let requireOnDevice = "requireOnDeviceTranscription"
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.showConsentReminder) private var showConsentReminder = true
    @AppStorage(SettingsKeys.requireOnDevice) private var requireOnDevice = true

    private var onDeviceSpeechSupported: Bool {
        SFSpeechRecognizer()?.supportsOnDeviceRecognition ?? false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Transcribe on this iPhone only", isOn: $requireOnDevice)
                    Toggle("Remind me to tell attendees", isOn: $showConsentReminder)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("When on-device transcription is required, speech never leaves this iPhone. If you turn it off, Apple's servers may be used for languages your iPhone can't transcribe itself.")
                }

                Section("This iPhone") {
                    status(
                        "On-device transcription",
                        ok: onDeviceSpeechSupported,
                        detail: Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier
                    )
                    status(
                        "Apple Intelligence notes",
                        ok: NotesEnhancers.isAppleIntelligenceAvailable,
                        detail: NotesEnhancers.isAppleIntelligenceAvailable
                            ? "Summaries and actions are written on this iPhone"
                            : "Not available, so basic extraction is used instead"
                    )
                }

                Section("How your data is handled") {
                    Label("Audio is never saved", systemImage: "waveform.slash")
                    Label("Transcripts and notes stay on this iPhone", systemImage: "iphone")
                    Label("Nothing is sent to Clear Notes or any third party", systemImage: "lock.shield")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                    Text("Phase 1: local capture on iPhone. Calendar, task-tool integrations and cross-meeting search come in Phase 2.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private func status(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle.fill")
                .foregroundStyle(ok ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
