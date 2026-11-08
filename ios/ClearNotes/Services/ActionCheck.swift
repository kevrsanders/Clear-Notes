import Foundation

/// Checks each action the notes found against what was said around it: the two turns before (what
/// "it" is, who asked) and the two after (whether it was taken on, by whom, by when). Only promises
/// and accepted requests are kept, each rewritten so it makes sense on its own, with a line of
/// context. A turn is everything one person says before someone else speaks.
///
/// Apple Intelligence does the check where it's available. Otherwise, or if it can't answer, rules
/// do: a request only counts when the next speaker accepts it.
enum ActionCheck {
    static let turnsBefore = 2
    static let turnsAfter = 2
    /// The most of the transcript sent with each check, so it fits the on-device model easily.
    static let excerptCharacterLimit = 2_400

    /// What a possible action turned out to be.
    enum Verdict: String, Sendable {
        /// Someone said they'll do it.
        case promise
        /// Someone was asked and agreed.
        case acceptedRequest
        /// Someone said a different person will do it.
        case passedOn
        /// They said no.
        case declined
        /// "We should…", with nobody taking it on.
        case idea
        case alreadyDone
        /// Something agreed by the group, not a task for a person.
        case decision
        case notATask

        /// Someone has taken it on.
        var isTask: Bool { self == .promise || self == .acceptedRequest || self == .passedOn }
    }

    struct Result: Sendable {
        var verdict: Verdict
        var action: ExtractedAction
    }

    /// Checks every action, in order. Keeps the ones someone took on, or every one (rewritten) with
    /// `keepAll`. Deadlines become dates, and repeats are merged.
    static func review(
        _ actions: [ExtractedAction],
        segments: [TranscriptSegment],
        speakers: [Speaker],
        meetingDate: Date,
        keepAll: Bool
    ) async -> [ExtractedAction] {
        var kept: [ExtractedAction] = []
        for action in actions {
            // From the user's own notes ("- [ ] …"), so nothing to check.
            guard action.evidence != nil else {
                kept.append(action)
                continue
            }
            let result = await check(action, segments: segments, speakers: speakers)
            guard keepAll || result.verdict.isTask else { continue }
            var checked = result.action
            checked.checked = result.verdict.isTask
            checked.due = checked.due.map { DueDate.resolved($0, from: meetingDate) }
            kept.append(checked)
        }
        return ActionList.merged(kept)
    }

    /// Checks one action against the turns around the line it was found in.
    static func check(_ action: ExtractedAction, segments: [TranscriptSegment], speakers: [Speaker]) async -> Result {
        guard let line = segments.segment(matching: action.evidence),
              let index = segments.firstIndex(where: { $0.id == line.id })
        else {
            // Not found in the transcript, so it can't be checked.
            return Result(verdict: .notATask, action: action)
        }
        let window = Self.window(around: index, in: segments)
        if let result = await aiCheck(action, window: window, line: line, speakers: speakers) {
            return result
        }
        return rulesCheck(action, window: window, line: line, speakers: speakers)
    }

    // MARK: - The turns around a line

    /// Runs of lines by the same speaker. A line with no speaker is a turn of its own.
    static func turns(in segments: [TranscriptSegment]) -> [Range<Int>] {
        guard !segments.isEmpty else { return [] }
        var turns: [Range<Int>] = []
        var start = 0
        for index in segments.indices.dropFirst() {
            let sameSpeaker = segments[index].speakerID != nil && segments[index].speakerID == segments[index - 1].speakerID
            if !sameSpeaker {
                turns.append(start..<index)
                start = index
            }
        }
        turns.append(start..<segments.count)
        return turns
    }

    /// The turn a line is in, with up to two turns either side. When that's too long, the lines
    /// furthest from it are left out.
    static func window(around index: Int, in segments: [TranscriptSegment]) -> [TranscriptSegment] {
        let allTurns = Self.turns(in: segments)
        guard let turn = allTurns.firstIndex(where: { $0.contains(index) }) else { return [] }
        var lower = allTurns[max(0, turn - turnsBefore)].lowerBound
        var upper = allTurns[min(allTurns.count - 1, turn + turnsAfter)].upperBound
        func length() -> Int { segments[lower..<upper].reduce(0) { $0 + $1.text.count + 24 } }
        while upper - lower > 1, length() > excerptCharacterLimit {
            if index - lower > upper - 1 - index {
                lower += 1
            } else {
                upper -= 1
            }
        }
        return Array(segments[lower..<upper])
    }

    /// The excerpt as the model sees it: "[12:04] Priya: …" lines, with ">>" before the line the
    /// action was found in.
    static func excerpt(_ window: [TranscriptSegment], line: UUID, speakers: [Speaker]) -> String {
        let labels = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.displayName) })
        return window.map { segment in
            let speaker = segment.speakerID.flatMap { labels[$0] } ?? "Unknown"
            let marker = segment.id == line ? ">> " : ""
            return "\(marker)[\(segment.start.clockString)] \(speaker): \(segment.text)"
        }.joined(separator: "\n")
    }

    // MARK: - Apple Intelligence

    private static func aiCheck(
        _ action: ExtractedAction,
        window: [TranscriptSegment],
        line: TranscriptSegment,
        speakers: [Speaker]
    ) async -> Result? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceEnhancer.isAvailable {
            guard let checked = await AppleIntelligenceEnhancer().checkAction(
                excerpt: excerpt(window, line: line.id, speakers: speakers),
                noted: action.task
            ) else { return nil }
            var rewritten = checked.action
            rewritten.evidence = action.evidence
            // Keep what the first pass found when the check leaves it out.
            rewritten.owner = rewritten.owner ?? action.owner
            rewritten.due = rewritten.due ?? action.due
            if rewritten.task.isEmpty { rewritten.task = action.task }
            return Result(verdict: checked.verdict, action: rewritten)
        }
        #endif
        return nil
    }

    // MARK: - Rules

    static let promiseCues = [
        "i will", "i'll", "i'm going to", "i am going to", "leave it with me", "i can do that",
        "i can do it", "i can take", "i'll take",
    ]
    static let requestCues = [
        "can you", "could you", "would you", "will you", "please can", "are you able to",
        "can i ask you to", "can i leave",
    ]
    static let acceptCues = [
        "yes", "yeah", "yep", "sure", "ok", "okay", "will do", "no problem", "of course", "fine",
        "i will", "i'll", "i can", "leave it with me", "happy to", "absolutely", "that's fine",
    ]
    static let declineCues = [
        "i can't", "i cannot", "i won't", "not me", "no i", "no not", "i'm not able", "i don't think i can",
        "can't do",
    ]
    static let ideaCues = [
        "we should", "we could", "it would be good", "it'd be good", "maybe we", "might be worth",
        "we ought to", "it would be nice", "wouldn't it be",
    ]
    static let doneCues = [
        "i've sent", "i have sent", "i've done", "i have done", "already done", "already sent",
        "i've already", "i have already", "i did that",
    ]

    /// The rules version of the check, on the line itself and the turn after it. The wording isn't
    /// changed, as rules can't rewrite it.
    static func rulesCheck(
        _ action: ExtractedAction,
        window: [TranscriptSegment],
        line: TranscriptSegment,
        speakers: [Speaker]
    ) -> Result {
        let names = Dictionary(uniqueKeysWithValues: speakers.compactMap { speaker in speaker.name.map { (speaker.id, $0) } })
        let said = action.evidence ?? line.text
        let words = HeuristicEnhancer.normalized(said)
        func has(_ cues: [String], in text: String) -> Bool { cues.contains { text.contains(" \($0) ") } }

        var result = action
        if has(doneCues, in: words) {
            return Result(verdict: .alreadyDone, action: result)
        }
        if has(promiseCues, in: words) {
            result.owner = result.owner ?? HeuristicEnhancer.owner(in: said) ?? line.speakerID.flatMap { names[$0] }
            return Result(verdict: .promise, action: result)
        }
        if has(requestCues, in: words) {
            // Asked: it only counts if the next person to speak takes it on.
            guard let reply = nextTurn(after: line, in: window) else {
                return Result(verdict: .notATask, action: result)
            }
            let opening = HeuristicEnhancer.normalized(reply.text.split(separator: " ").prefix(14).joined(separator: " "))
            if has(declineCues, in: opening) {
                return Result(verdict: .declined, action: result)
            }
            guard has(acceptCues, in: opening) else {
                return Result(verdict: .notATask, action: result)
            }
            result.owner = result.owner ?? reply.speakerID.flatMap { names[$0] }
            return Result(verdict: .acceptedRequest, action: result)
        }
        if has(ideaCues, in: words) {
            return Result(verdict: .idea, action: result)
        }
        // "Priya will send it": someone else's commitment, said by another person.
        if let owner = HeuristicEnhancer.owner(in: said) {
            result.owner = result.owner ?? owner
            return Result(verdict: .passedOn, action: result)
        }
        return Result(verdict: .notATask, action: result)
    }

    /// The first line by someone else after this one, within the window.
    private static func nextTurn(after line: TranscriptSegment, in window: [TranscriptSegment]) -> TranscriptSegment? {
        guard let index = window.firstIndex(where: { $0.id == line.id }) else { return nil }
        return window[(index + 1)...].first { segment in
            segment.speakerID == nil || segment.speakerID != line.speakerID
        }
    }
}

/// Turns a deadline said in a meeting into a date: "by Friday" said on Wednesday 12 November
/// becomes "by Fri 14 Nov". Anything it can't place is left as it was said.
enum DueDate {
    private static let weekdays = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]

    static func resolved(_ due: String, from date: Date, calendar: Calendar = .current) -> String {
        let pattern = #/^(?:(?<prep>by|before|on|until)\s+)?(?:(?<which>next|this)\s+)?(?<when>[a-z ]+?)$/#
        let text = due.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        guard let match = text.firstMatch(of: pattern) else { return due }
        let prep = match.output.prep.map(String.init)
        let which = match.output.which.map(String.init)
        let when = String(match.output.when)

        let today = mondayIndex(of: date, calendar: calendar)
        let offset: Int?
        switch when {
        case "today", "end of the day", "end of day", "end of play", "close of play", "eod", "cob":
            offset = which == nil ? 0 : nil
        case "tomorrow":
            offset = which == nil ? 1 : nil
        case "end of the week", "end of this week", "the end of the week", "the end of this week":
            let friday = 4 - today
            offset = friday >= 0 ? friday : nil
        default:
            guard let day = weekdays.firstIndex(of: when) else { return due }
            let coming = (day - today + 7) % 7 == 0 ? 7 : (day - today + 7) % 7
            switch which {
            case "next": offset = (7 - today) + day
            case "this": offset = day - today > 0 ? day - today : coming
            default: offset = coming
            }
        }
        guard let offset,
              let target = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: date))
        else { return due }
        return [prep, format(target)].compactMap { $0 }.joined(separator: " ")
    }

    /// "Fri 14 Nov", as the action editor writes dates.
    static func format(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// Monday 0 to Sunday 6.
    private static func mondayIndex(of date: Date, calendar: Calendar) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }
}
