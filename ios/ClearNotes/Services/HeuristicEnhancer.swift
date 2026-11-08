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

        let summary = Self.summary(segments: segments, userNotes: userNotes)
        let topics = Self.topics(in: segments)
        return MeetingInsights(
            title: nil,
            summary: summary,
            decisions: Self.unique(decisions),
            actions: Self.unique(actions, by: \.task),
            topics: topics.isEmpty ? Self.wholeMeetingTopic(segments: segments, summary: summary) : topics
        )
    }

    /// One topic for a meeting too short to split, so its page still has topics: its main words
    /// for a title, and the summary's points.
    static func wholeMeetingTopic(segments: [TranscriptSegment], summary: String) -> [Topic] {
        guard let first = segments.first, let last = segments.last else { return [] }
        let keywords = Self.keywords(in: segments.map(\.text).joined(separator: " "), limit: 2)
        // Only real points, not "Short meeting. See the transcript for details."
        let points = summary.hasPrefix("-") ? NotesText.bullets(from: summary).prefix(5) : []
        guard !keywords.isEmpty, !points.isEmpty else { return [] }
        let title = keywords.joined(separator: " and ")
        return [Topic(
            title: title.prefix(1).uppercased() + title.dropFirst(),
            start: first.start,
            end: last.end,
            points: Array(points)
        )]
    }

    // MARK: - Topics

    /// Target length of a topic window. Meetings shorter than two windows get no topics.
    static let topicWindow: TimeInterval = 5 * 60

    /// Splits the meeting into roughly five-minute windows (at line boundaries) and titles
    /// each one with its most frequent meaningful words, e.g. "Budget and hosting".
    static func topics(in segments: [TranscriptSegment]) -> [Topic] {
        guard let first = segments.first, let last = segments.last,
              last.end - first.start >= topicWindow * 2
        else { return [] }

        var windows: [[TranscriptSegment]] = [[]]
        var windowStart = first.start
        for segment in segments {
            if segment.start - windowStart >= topicWindow && !windows[windows.count - 1].isEmpty {
                windows.append([])
                windowStart = segment.start
            }
            windows[windows.count - 1].append(segment)
        }

        return windows.compactMap { window in
            guard let start = window.first?.start, let end = window.last?.end else { return nil }
            let keywords = Self.keywords(in: window.map(\.text).joined(separator: " "), limit: 2)
            guard !keywords.isEmpty else { return nil }
            let title = keywords.joined(separator: " and ")
            let points = window
                .flatMap { segment -> [String] in sentences(in: segment.text) }
                .filter { $0.split(separator: " ").count >= 6 }
                .sorted { $0.count > $1.count }
                .prefix(2)
            return Topic(
                title: title.prefix(1).uppercased() + title.dropFirst(),
                start: start,
                end: end,
                points: Array(points)
            )
        }
    }

    /// The most frequent words that carry meaning (not filler or common words).
    static func keywords(in text: String, limit: Int) -> [String] {
        var counts: [String: Int] = [:]
        for word in normalized(text).split(separator: " ") where word.count >= 4 {
            let key = String(word)
            if !stopWords.contains(key) && !key.contains("'") {
                counts[key, default: 0] += 1
            }
        }
        return counts
            .filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    private static let stopWords: Set<String> = [
        "about", "above", "actually", "after", "again", "against", "also", "always", "another", "anyone",
        "anything", "around", "back", "basically", "because", "been", "before", "being", "below", "best",
        "better", "between", "both", "bring", "call", "came", "come", "could", "didn", "does", "doing",
        "done", "down", "during", "each", "else", "enough", "even", "ever", "every", "everyone", "fine",
        "first", "from", "further", "gets", "getting", "give", "going", "gone", "good", "great", "guess",
        "have", "having", "hear", "here", "honestly", "into", "just", "keep", "kind", "know", "last", "later",
        "least", "less", "like", "little", "long", "look", "looking", "made", "make", "many", "maybe", "mean",
        "might", "more", "most", "much", "must", "need", "needs", "never", "next", "nice", "obviously", "okay",
        "once", "only", "other", "over", "part", "people", "point", "pretty", "probably", "quite", "really",
        "right", "said", "same", "saying", "says", "seem", "should", "since", "some", "something", "sort",
        "still", "sure", "take", "talk", "talking", "tell", "than", "thank", "thanks", "that", "their", "them",
        "then", "there", "these", "they", "thing", "things", "think", "this", "those", "though", "thought",
        "through", "time", "today", "together", "very", "want", "wanted", "week", "well", "went", "were",
        "what", "when", "where", "whether", "which", "while", "will", "with", "within", "without", "work",
        "would", "yeah", "year", "your", "yours",
    ]

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
            .flatMap { segment -> [String] in sentences(in: segment.text) }
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
