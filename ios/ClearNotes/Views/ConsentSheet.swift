import SwiftUI

/// Reminds the user to tell attendees before transcribing.
struct ConsentSheet: View {
    @AppStorage(SettingsKeys.showConsentReminder) private var showConsentReminder = true
    var onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            IconTile(systemName: "person.wave.2.fill", tint: nil, size: 52)

            VStack(alignment: .leading, spacing: 6) {
                Text("Before you start")
                    .font(.system(size: 28, weight: .bold))
                    .tracking(-0.4)
                Text("A quick check so everyone is comfortable.")
                    .foregroundStyle(Theme.textSecondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                point("megaphone.fill", "Tell everyone you're taking AI-assisted notes.")
                point("lock.iphone", "Speech is transcribed on this iPhone. " + AudioRetention.current.promise)
                point("cross.case.fill", "Don't use Clear Notes for clinical consultations or patient information.")
            }

            Spacer(minLength: 0)

            Toggle("Remind me each time", isOn: $showConsentReminder)
                .font(.subheadline)
                .tint(Theme.brand)

            Button(action: onStart) {
                HStack(spacing: 10) {
                    Image(systemName: "mic.fill")
                    Text("Start recording")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(Theme.recordGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .background(Theme.background)
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.brand)
                .frame(width: 34, height: 34)
                .background(Theme.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
