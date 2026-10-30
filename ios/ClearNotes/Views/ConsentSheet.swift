import SwiftUI

/// Reminds the user to tell attendees before transcribing.
struct ConsentSheet: View {
    @AppStorage(SettingsKeys.showConsentReminder) private var showConsentReminder = true
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Image(systemName: "person.wave.2.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            Text("Before you start")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 14) {
                point("megaphone", "Tell everyone in the meeting that you're taking AI-assisted notes.")
                point("lock.iphone", "Speech is transcribed on this iPhone. Audio is never saved.")
                point("cross.case", "Don't use Clear Notes for clinical consultations or to record patient information.")
            }

            Spacer(minLength: 0)

            Toggle("Remind me each time", isOn: $showConsentReminder)
                .font(.subheadline)

            Button(action: onStart) {
                Text("Start recording")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.record)
            .controlSize(.large)
        }
        .padding(24)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.tint)
                .frame(width: 28)
        }
        .font(.body)
    }
}
