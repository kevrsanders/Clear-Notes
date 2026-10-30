import Foundation

/// Rule-based extraction for iPhones without Apple Intelligence.
/// It looks for commitment and decision phrases ("I'll send…", "we agreed…") and for
/// lines the user marked as actions or decisions in their own notes.
struct HeuristicEnhancer: NotesEnhancer {
    let sourceName = "Basic on-device extraction"

    static let actionCues = [
        "i will", "i'll", "we will", "we'll", "you will", "you'll", "will send", "will share",
        "will follow up", "can you", "could you", "action point", "to do", "todo",
        "needs to", "need to", "follow up", "going to", "take that away", "take away", "let me",
    ]
    /// Commitments the speaker makes themselves, so the speaker is the owner.
    static let firstPersonCues = ["i will", "i'll", "i can", "i'm going to", "i am going to", "let me", "i need to"]
    static let decisionCues = [
        "we agreed", "agreed that", "we've agreed", "we decided", "decided to", "the decision",
        "let's go with", "we'll go with", "signed off", "approved",
    ]
    private static let notOwners: Set<String> = [
        "I", "We", "You", "They", "So", "And", "Then", "The", "It", "That", "This", "Someone",
        "Somebody", "Everyone", "But", "Okay", "Ok", "Yes", "No", "Also", "Just",
    ]

    func enhance(segments: [TranscriptSegment], speakers: [Speaker], userNotes: String) async throws -> MeetingInsights {
        let names = Dictionary(uniqueKeysWithValues: speakers.compactMap { speaker in speaker.name.map { (speaker.id, $0) } })
        var decisions: [String] = []
        var actions: [ExtractedAction] = []

        for line in userNotes.split(whereSeparator: \.isNewline).map(String.init) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let task = Self.stripPrefix(trimmed, prefixes: ["- [ ]", "[ ]", "action:", "todo:"]) {
                actions.append(ExtractedAction(task: task, owner: Self.owner(in: task), due: Self.due(in: task)))
            } else if let decision = Self.stripPrefix(trimmed, prefixes: ["decision:", "decided:"]) {
                decisions.append(decision)
            }
        }

        for segment in segments {
            let speakerName = segment.speakerID.flatMap { names[$0] }
            for sentence in Self.sentences(in: segment.text) {
                let words = Self.normalized(sentence)
                if Self.decisionCues.contains(where: { words.contains(" \($0) ") }) {
                    decisions.append(sentence)
                } else if Self.actionCues.contains(where: { words.contains(" \($0) ") }) {
                    let isOwnCommitment = Self.firstPersonCues.contains { words.contains(" \($0) ") }
                    actions.append(ExtractedAction(
                        task: sentence,
                        owner: Self.owner(in: sentence) ?? (isOwnCommitment ? speakerName : nil),
                        due: Self.due(in: sentence),
                        evidence: sentence
                    ))
                }
            }
        }

        return MeetingInsights(
            title: nil,
            summary: Self.summary(segments: segments, userNotes: userNotes),
            decisions: Self.unique(decisions),
            actions: Self.unique(actions, by: \.task)
        )
    }

    // MARK: - Helpers

    /// Lower-cased words separated by single spaces, padded with a space at each end,
    /// so cues match whole words only ("taxi will" doesn't match "i will").
    static func normalized(_ text: String) -> String {
        let mapped = text.lowercased().map { character -> Character in
            if character == "\u{2019}" { return "'" }
            return character.isLetter || character.isNumber || character == "'" ? character : " "
        }
        return " " + String(mapped).split(separator: " ").joined(separator: " ") + " "
    }

    static func sentences(in text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { substring, _, _, _ in
            if let sentence = substring?.trimmingCharacters(in: .whitespacesAndNewlines), sentence.count > 3 {
                result.append(sentence)
            }
        }
        return result
    }

    /// A capitalised name directly before a commitment, e.g. "Priya will…" → "Priya".
    static func owner(in sentence: String) -> String? {
        let pattern = #/(?<name>[A-Z][a-z]+)(?:'ll| will| is going to| needs to| to follow up)\b/#
        for match in sentence.matches(of: pattern) {
            let name = String(match.output.name)
            if !notOwners.contains(name) { return name }
        }
        return nil
    }

    /// A stated deadline such as "by Friday", "next week" or "end of the month".
    static func due(in sentence: String) -> String? {
        let pattern = #/\b(?:(?:by|before|on|until)\s+)?(?:next\s+|this\s+)?(?:monday|tuesday|wednesday|thursday|friday|tomorrow|week|month|(?:the\s+)?end\s+of\s+(?:the\s+)?(?:day|week|month))\b/#
            .ignoresCase()
        guard let match = sentence.firstMatch(of: pattern) else { return nil }
        let text = String(sentence[match.range])
        // "week" or "month" on its own isn't a deadline.
        if ["week", "month"].contains(text.lowercased()) { return nil }
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    static func summary(segments: [TranscriptSegment], userNotes: String) -> String {
        let noteLines = userNotes
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !noteLines.isEmpty {
            return noteLines.prefix(8).map { $0.hasPrefix("-") ? $0 : "- \($0)" }.joined(separator: "\n")
        }
        let longest = segments
            .flatMap { sentences(in: $0.text) }
            .filter { $0.split(separator: " ").count >= 8 }
            .prefix(3)
        if longest.isEmpty {
            return segments.isEmpty ? "Nothing was transcribed." : "Short meeting. See the transcript for details."
        }
        return longest.map { "- \($0)" }.joined(separator: "\n")
    }

    private static func stripPrefix(_ line: String, prefixes: [String]) -> String? {
        let lower = line.lowercased()
        for prefix in prefixes where lower.hasPrefix(prefix) {
            let rest = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? nil : rest
        }
        return nil
    }

    private static func unique(_ items: [String]) -> [String] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func unique<T>(_ items: [T], by key: KeyPath<T, String>) -> [T] {
        var seen = Set<String>()
        return items.filter { seen.insert($0[keyPath: key].lowercased()).inserted }
    }
}
