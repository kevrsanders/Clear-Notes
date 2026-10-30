import SwiftUI

/// The main floating "New meeting" button.
struct RecordButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "mic.fill")
                    .font(.body.weight(.semibold))
                Text("New meeting")
                    .font(.headline)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 26)
            .padding(.vertical, 16)
            .background(Theme.record, in: Capsule())
            .shadow(color: Theme.record.opacity(0.35), radius: 14, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Starts recording and transcribing a meeting on this iPhone")
    }
}
