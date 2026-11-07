import SwiftUI

/// Settings → Transcription → My words: names and terms the transcript should spell correctly.
struct VocabularyView: View {
    @AppStorage(SettingsKeys.customVocabulary) private var customVocabulary = ""
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("One name or term per line. After each meeting, words the transcript almost certainly misheard are corrected to these spellings, for example \"in tune\" to \"Intune\". Real words that are only close aren't changed.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                ZStack(alignment: .topLeading) {
                    if customVocabulary.isEmpty {
                        Text("Intune\nNHSmail\nPriya Sharma")
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                    }
                    TextEditor(text: $customVocabulary)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .frame(minHeight: 220)
                }
                .cardStyle(padding: 12)

                Text("People invited to a meeting, named speakers and your own name are included automatically.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { ScreenBackground() }
        .navigationTitle("My words")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focused {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { focused = false }
                }
            }
        }
    }
}
