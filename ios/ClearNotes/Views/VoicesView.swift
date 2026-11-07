import SwiftData
import SwiftUI

/// Remembered voices: who is recognised, and a way to forget them.
struct VoicesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \VoiceProfile.name) private var profiles: [VoiceProfile]
    @State private var confirmDeleteAll = false

    var body: some View {
        List {
            Section {
                if profiles.isEmpty {
                    Text("No voices remembered yet. When you name a speaker, turn on Remember this voice (with their agreement).")
                        .foregroundStyle(Theme.textSecondary)
                }
                ForEach(profiles) { profile in
                    HStack(spacing: 12) {
                        Avatar(name: profile.name, color: Theme.brand, size: 36, textColor: Theme.onBrand)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.body.weight(.medium))
                            Text("Agreed \(profile.consentedAt.formatted(date: .abbreviated, time: .omitted)) · confirmed \(profile.confirmations)×")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { profiles[$0] }.forEach { context.delete($0) }
                    try? context.save()
                }
            } footer: {
                Text("Voiceprints are biometric data. They stay on this iPhone, are only saved with the person's agreement, and are used only to suggest names. Swipe to forget someone.")
            }

            if !profiles.isEmpty {
                Section {
                    Button("Forget all voices", role: .destructive) { confirmDeleteAll = true }
                }
            }
        }
        .navigationTitle("Voices")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Forget all voices?", isPresented: $confirmDeleteAll, titleVisibility: .visible) {
            Button("Forget all voices", role: .destructive) {
                VoiceLibrary.deleteAll(in: context)
            }
        } message: {
            Text("Every remembered voice and the voiceprints kept on meetings are deleted. Names already on meetings stay.")
        }
    }
}
