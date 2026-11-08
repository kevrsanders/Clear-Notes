import Foundation

/// How keen Clear Notes is to suggest actions it found itself (Settings → Actions).
enum ActionSuggestions: String, CaseIterable, Identifiable {
    /// Only moments the user marked, by tapping or with a spoken phrase.
    case markedOnly
    /// Marked moments plus explicit promises and requests ("I'll send it by Friday", "Can you…").
    case commitments
    /// Everything the notes found, as before.
    case everything

    static let `default` = ActionSuggestions.commitments

    static var current: ActionSuggestions {
        UserDefaults.standard.string(forKey: SettingsKeys.actionSuggestions).flatMap(Self.init(rawValue:)) ?? .default
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .markedOnly: "Only what I mark"
        case .commitments: "Marked plus clear commitments"
        case .everything: "Everything it finds"
        }
    }

    var explanation: String {
        switch self {
        case .markedOnly:
            "Only moments you mark become actions: tap Mark action while recording, or say \"action point\"."
        case .commitments:
            "Marked moments, plus clear promises and requests such as \"I'll send it by Friday\" or \"Can you book the room?\". At most about one suggestion for every five minutes."
        case .everything:
            "Every possible action the notes find, for you to accept or dismiss."
        }
    }
}

/// Phrases people say to flag an action or decision, found in the transcript after the meeting.
enum SpokenMarks {
    static let actionPhrases = [
        "action point", "action item", "action for", "an action on", "capture that as an action",
        "capture an action", "take an action", "that's an action", "that is an action", "log an action",
        "add an action",
    ]
    static let decisionPhrases = [
        "decision point", "record that as a decision", "record the decision", "log a decision",
        "that's a decision", "that is a decision", "the decision is",
    ]

    /// Marks for lines containing a trigger phrase. A phrase within 30 seconds of a tap of the same
    /// kind is the same moment, so it's skipped. Each mark takes the line's ID, so processing the
    /// meeting again finds the same marks.
    static func find(in segments: [TranscriptSegment], besides taps: [MeetingMark]) -> [MeetingMark] {
        var found: [MeetingMark] = []
        for segment in segments {
            let words = HeuristicEnhancer.normalized(segment.text)
            let kind: MeetingMark.Kind
            if actionPhrases.contains(where: { words.contains(" \($0) ") }) {
                kind = .action
            } else if decisionPhrases.contains(where: { words.contains(" \($0) ") }) {
                kind = .decision
            } else {
                continue
            }
            let nearby = (taps + found).contains { $0.kind == kind && abs($0.time - segment.end) <= 30 }
            guard !nearby else { continue }
            found.append(MeetingMark(id: segment.id, kind: kind, time: segment.end, source: .spoken))
        }
        return found
    }
}

/// Decides which of the actions the notes found are worth suggesting.
enum ActionPolicy {
    /// Words that show someone promised or was asked to do something. Not "I can", "let me" or
    /// "we'll", which are as often "I can see why", "let me think" or "we'll see".
    static let commitmentCues = [
        "i will", "i'll", "i'm going to", "i am going to", "i'll make sure",
        "can you", "could you", "would you", "will you", "please can",
        "action for", "action point", "leave it with me", "i'll take",
    ]

    /// About one suggestion for every five minutes, and at least two.
    static func cap(forDuration duration: TimeInterval) -> Int {
        max(2, Int(duration / 300))
    }

    static func isClearCommitment(_ action: ExtractedAction) -> Bool {
        // Checked against what was said around it, and someone took it on.
        if action.checked == true { return true }
        if action.owner != nil && action.due != nil { return true }
        guard let evidence = action.evidence else { return false }
        let words = HeuristicEnhancer.normalized(evidence)
        return commitmentCues.contains { words.contains(" \($0) ") }
    }

    /// The suggestions to show, in meeting order. Nothing repeats a decision or a marked action.
    static func suggestions(
        from actions: [ExtractedAction],
        decisions: [String],
        marked: [ExtractedAction],
        duration: TimeInterval,
        setting: ActionSuggestions
    ) -> [ExtractedAction] {
        guard setting != .markedOnly else { return [] }
        let candidates = ActionList.deduplicated(actions).filter { action in
            !decisions.contains { ActionList.similar(action.task, $0) }
                && !marked.contains { ActionList.similar(action.task, $0.task) }
        }
        guard setting == .commitments else { return candidates }

        let room = max(0, cap(forDuration: duration) - marked.count)
        let committed = candidates.enumerated().filter { isClearCommitment($0.element) }
        // Prefer the most specific (owner and date, then owner), keeping meeting order otherwise.
        let chosen = committed
            .sorted { first, second in
                let firstScore = specificity(first.element)
                let secondScore = specificity(second.element)
                return firstScore != secondScore ? firstScore > secondScore : first.offset < second.offset
            }
            .prefix(room)
            .map { $0.offset }
        return Set(chosen).sorted().map { candidates[$0] }
    }

    private static func specificity(_ action: ExtractedAction) -> Int {
        (action.owner != nil ? 2 : 0) + (action.due != nil ? 1 : 0)
    }
}

/// What the marked moments became.
struct MarkedItems: Sendable {
    var actions: [ExtractedAction] = []
    var decisions: [String] = []
}

/// Turns each marked moment into an action or decision, from what was said just before it.
enum MarkWriter {
    /// What's said in the 45 seconds before a mark (and a little after, for "action point: …").
    static let lookBack: TimeInterval = 45
    static let lookAhead: TimeInterval = 10

    static func window(for mark: MeetingMark, in segments: [TranscriptSegment]) -> [TranscriptSegment] {
        segments.filter { $0.end >= mark.time - lookBack && $0.start <= mark.time + lookAhead }
    }

    static func write(_ marks: [MeetingMark], segments: [TranscriptSegment], speakers: [Speaker]) async -> MarkedItems {
        var items = MarkedItems()
        for mark in marks.sorted(by: { $0.time < $1.time }) {
            let said = Self.window(for: mark, in: segments)
            guard !said.isEmpty else { continue }
            switch mark.kind {
            case .action:
                var action = await aiAction(window: said, mark: mark, speakers: speakers)
                    ?? HeuristicEnhancer.markedAction(in: said, before: mark.time, speakers: speakers)
                action.markID = mark.id
                items.actions.append(action)
            case .decision:
                let decision = await aiDecision(window: said, mark: mark, speakers: speakers)
                    ?? HeuristicEnhancer.markedDecision(in: said, before: mark.time)
                if let decision, !items.decisions.contains(decision) {
                    items.decisions.append(decision)
                }
            }
        }
        return items
    }

    /// The excerpt as the model sees it: "[12:04] Priya: …" lines.
    static func excerpt(_ window: [TranscriptSegment], speakers: [Speaker]) -> String {
        let labels = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.displayName) })
        return window.map { segment in
            let speaker = segment.speakerID.flatMap { labels[$0] } ?? "Unknown"
            return "[\(segment.start.clockString)] \(speaker): \(segment.text)"
        }.joined(separator: "\n")
    }

    private static func aiAction(window: [TranscriptSegment], mark: MeetingMark, speakers: [Speaker]) async -> ExtractedAction? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceEnhancer.isAvailable {
            return await AppleIntelligenceEnhancer().markedAction(
                excerpt: excerpt(window, speakers: speakers),
                markedAt: mark.time.clockString,
                spoken: mark.source == .spoken
            )
        }
        #endif
        return nil
    }

    private static func aiDecision(window: [TranscriptSegment], mark: MeetingMark, speakers: [Speaker]) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceEnhancer.isAvailable {
            return await AppleIntelligenceEnhancer().markedDecision(
                excerpt: excerpt(window, speakers: speakers),
                markedAt: mark.time.clockString,
                spoken: mark.source == .spoken
            )
        }
        #endif
        return nil
    }
}

extension HeuristicEnhancer {
    /// The action a mark points to: the last promise or request said before it, or else the last
    /// thing said. The owner is a name in the sentence, or the speaker for "I'll…".
    static func markedAction(in window: [TranscriptSegment], before time: TimeInterval, speakers: [Speaker]) -> ExtractedAction {
        let names = Dictionary(uniqueKeysWithValues: speakers.compactMap { speaker in speaker.name.map { (speaker.id, $0) } })
        let said = sentences(in: window, before: time)
        let chosen = said.last { line in
            let words = normalized(line.sentence)
            return actionCues.contains { words.contains(" \($0) ") }
        } ?? said.last
        guard let chosen else {
            return ExtractedAction(task: "Action marked at \(time.clockString)")
        }
        let sentence = chosen.sentence
        let speaker = chosen.speakerID.flatMap { names[$0] }
        let words = normalized(sentence)
        let ownCommitment = firstPersonCues.contains { words.contains(" \($0) ") }
        return ExtractedAction(
            task: sentence,
            owner: owner(in: sentence) ?? (ownCommitment ? speaker : nil),
            due: due(in: sentence),
            evidence: sentence
        )
    }

    /// The decision a mark points to: the last thing said that sounds agreed, or else the last thing said.
    static func markedDecision(in window: [TranscriptSegment], before time: TimeInterval) -> String? {
        let said = sentences(in: window, before: time).map { $0.sentence }
        return said.last { sentence in
            let words = normalized(sentence)
            return decisionCues.contains { words.contains(" \($0) ") }
        } ?? said.last
    }

    /// Sentences said up to just after a moment, in order, with who said them.
    private static func sentences(in window: [TranscriptSegment], before time: TimeInterval) -> [(sentence: String, speakerID: String?)] {
        window
            .filter { $0.start <= time + 2 }
            .flatMap { segment in sentences(in: segment.text).map { (sentence: $0, speakerID: segment.speakerID) } }
    }
}
