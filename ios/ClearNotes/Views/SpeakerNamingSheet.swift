import SwiftData
import SwiftUI

/// Names one speaker everywhere in a meeting. Shows what they said, suggests names
/// from earlier meetings, and can merge two voices that belong to the same person.
struct SpeakerNamingSheet: View {
    @Bindable var meeting: Meeting
    let speaker: Speaker
    /// Plays the recording between two times, when the recording is kept.
    var onPlay: ((TimeInterval, TimeInterval?) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKeys.rememberVoices) private var rememberVoices = false
    @State private var rememberThisVoice = false
    @State private var suggestionRejected = false
    @Query(filter: #Predicate<Meeting> { $0.deletedAt == nil }) private var allMeetings: [Meeting]
    @AppStorage(SettingsKeys.myName) private var myName = ""
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var color: Color { Theme.speakerColor(number: speaker.number) }

    /// The speaker's two longest lines, in the order they were said.
    private var quotes: [TranscriptSegment] {
        meeting.segments
            .filter { $0.speakerID == speaker.id }
            .sorted { $0.text.count > $1.text.count }
            .prefix(2)
            .sorted { $0.start < $1.start }
    }

    /// "Me", people invited to this meeting, then people from earlier meetings and action owners,
    /// skipping names already used here.
    private var suggestions: [String] {
        let me = myName.trimmingCharacters(in: .whitespaces)
        var candidates = [me.isEmpty ? "Me" : me] + meeting.attendees
        for other in allMeetings.sorted(by: { $0.createdAt > $1.createdAt }) {
            candidates += other.speakers.compactMap(\.name)
            candidates += other.actions.compactMap(\.owner)
        }
        let taken = Set(meeting.speakers.filter { $0.id != speaker.id }.compactMap { $0.name?.lowercased() })
        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = candidate.lowercased()
            return !taken.contains(key) && seen.insert(key).inserted
        }
        .prefix(10)
        .map { $0 }
    }

    private var otherSpeakers: [Speaker] {
        meeting.speakers.filter { $0.id != speaker.id }
    }

    /// "Spoke 3 times · 1 min 12 s"
    private var spokeSummary: String {
        let lines = meeting.segments.filter { $0.speakerID == speaker.id }
        let seconds = Int(lines.reduce(0) { $0 + ($1.end - $1.start) })
        let time = seconds >= 60 ? "\(seconds / 60) min \(seconds % 60) s" : "\(seconds) s"
        return "Spoke \(lines.count) time\(lines.count == 1 ? "" : "s") · \(time)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(spacing: 12) {
                    Avatar(speaker: speaker, size: 72)
                    Text("Who is \(speaker.displayName)?")
                        .font(.title2.bold())
                    Text(spokeSummary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                if let suggested = speaker.suggestedName, !suggestionRejected {
                    suggestionCard(suggested)
                }

                if !quotes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("They said")
                        ForEach(quotes) { quote in
                            HStack(alignment: .top, spacing: 12) {
                                Capsule().fill(color).frame(width: 3)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(quote.start.clockString)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(Theme.textSecondary)
                                    Text("“\(quote.text)”")
                                        .italic()
                                        .lineLimit(4)
                                }
                                Spacer(minLength: 0)
                                if let onPlay {
                                    Button {
                                        onPlay(quote.start, quote.end)
                                    } label: {
                                        Image(systemName: "play.fill")
                                            .font(.system(size: 13, weight: .bold))
                                            .foregroundStyle(color)
                                            .frame(width: 34, height: 34)
                                            .background(color.opacity(0.14), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Play this line")
                                }
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            .cardStyle(padding: 14)
                        }
                    }
                }

                if rememberVoices && speaker.embedding != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $rememberThisVoice) {
                            Label("Remember this voice", systemImage: "person.wave.2.fill")
                        }
                        .tint(Theme.brand)
                        Text("Only with their agreement. Their voiceprint stays on this iPhone and is used to suggest their name in later meetings.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .cardStyle(padding: 14)
                }

                HStack(spacing: 10) {
                    TextField("Enter a name", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit { save(name) }
                        .padding(.horizontal, 18)
                        .frame(height: 50)
                        .glass(in: Capsule())
                    Button("Save") { save(name) }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Suggestions")
                        FlowLayout(spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button {
                                    save(suggestion)
                                } label: {
                                    PersonChip(name: suggestion, color: Theme.brand)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Name as \(suggestion)")
                            }
                        }
                    }
                }

                if !otherSpeakers.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("Same person as")
                        FlowLayout(spacing: 8) {
                            ForEach(otherSpeakers) { other in
                                Button {
                                    meeting.mergeSpeaker(speaker.id, into: other.id)
                                    dismiss()
                                } label: {
                                    PersonChip(speaker: other)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Same person as \(other.displayName)")
                            }
                        }
                    }
                }

                if speaker.name != nil {
                    Button("Remove name", role: .destructive) { save(nil) }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(Theme.gutter)
        }
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            GlassCircleButton(systemName: "xmark", accessibilityLabel: "Close") { dismiss() }
                .padding(16)
        }
        .onAppear { name = speaker.name ?? "" }
        .sensoryFeedback(.success, trigger: meeting.speakers)
    }

    private func save(_ newName: String?) {
        meeting.renameSpeaker(speaker.id, to: newName)
        if rememberThisVoice, let newName, let embedding = speaker.embedding {
            VoiceLibrary.remember(name: newName, embedding: embedding, in: context)
        }
        dismiss()
    }

    /// "Sounds like Priya": confirming names the speaker and strengthens the remembered voice.
    private func suggestionCard(_ suggested: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(systemName: "person.wave.2.fill", tint: nil, size: 32)
                Text("Sounds like **\(suggested)**")
                    .font(.headline)
            }
            HStack(spacing: 8) {
                Button {
                    meeting.confirmSuggestion(for: speaker.id)
                    if let embedding = speaker.embedding {
                        VoiceLibrary.remember(name: suggested, embedding: embedding, in: context)
                    }
                    dismiss()
                } label: {
                    Label("Yes, it's \(suggested)", systemImage: "checkmark")
                }
                .buttonStyle(PrimaryButtonStyle(compact: true))

                Button("Not them") {
                    meeting.rejectSuggestion(for: speaker.id)
                    suggestionRejected = true
                }
                .buttonStyle(SecondaryButtonStyle(compact: true))
            }
        }
        .cardStyle(padding: 16)
    }
}

/// A tappable person: small avatar plus name in a capsule.
private struct PersonChip: View {
    var name: String?
    var color: Color
    var placeholder = "?"

    init(name: String, color: Color) {
        self.name = name
        self.color = color
    }

    init(speaker: Speaker) {
        name = speaker.name
        color = Theme.speakerColor(number: speaker.number)
        placeholder = "\(speaker.number)"
        label = speaker.displayName
    }

    private var label: String?

    var body: some View {
        HStack(spacing: 8) {
            Avatar(name: name, color: color, size: 26, placeholder: placeholder)
            Text(label ?? name ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.leading, 4)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
