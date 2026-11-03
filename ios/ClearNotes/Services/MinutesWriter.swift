import Foundation
import Observation
import SwiftData
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Formal minutes, as a minute-taker would write them: who was present, a numbered item for each
/// part of the meeting with what was discussed in reported speech ("Priya reported that…"), what
/// was agreed and the actions, then a summary of actions.
///
/// The minutes are plain text, so they paste cleanly into an email, Word or Teams and the user can
/// edit them. Numbered lines ("1.", "1.1", "Agreed:", "Action:") are styled by `MinutesFormat`.
enum MinutesWriter {
    /// One part of the meeting, which becomes a numbered item.
    struct Part: Equatable, Sendable {
        /// The topic's title from the notes, or nil to have one written.
        var title: String?
        var start: TimeInterval
        var end: TimeInterval
        /// "[1:05] Priya Sharma: …" lines.
        var transcript: String
        var segments: [TranscriptSegment]
        /// The topic's key points from the notes, used when the minutes can't be written by AI.
        var keyPoints: [String]
    }

    struct Decision: Equatable, Sendable {
        var text: String
        /// When it was said, to place it under the right item.
        var time: TimeInterval?
    }

    struct Action: Equatable, Sendable {
        var text: String
        var owner: String?
        var due: String?
        var isDone: Bool
        var time: TimeInterval?
    }

    struct Input: Sendable {
        var title: String
        var start: Date
        var duration: TimeInterval
        /// Named speakers, in order of first speaking.
        var present: [String]
        var unnamedSpeakers: Int
        var parts: [Part]
        var decisions: [Decision]
        /// Accepted actions only: suggestions haven't been checked by a person yet.
        var actions: [Action]
        var speakers: [Speaker]
    }

    /// A written item: its heading and what was discussed.
    struct Item: Equatable, Sendable {
        var title: String
        var points: [String]
    }

    struct Draft: Sendable {
        var text: String
        var source: String
    }

    // MARK: - Writing

    static func write(_ input: Input, progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async -> Draft {
        var items: [Item] = []
        var written = 0
        for (index, part) in input.parts.enumerated() {
            await progress(index + 1, input.parts.count)
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *), AppleIntelligenceEnhancer.isAvailable,
               let item = try? await AIMinutes.item(for: part) {
                items.append(item)
                written += 1
                continue
            }
            #endif
            items.append(await basicItem(for: part, isOnlyPart: input.parts.count == 1, speakers: input.speakers))
        }

        let source: String
        if input.parts.isEmpty || written == input.parts.count {
            source = written > 0 ? "Written on this iPhone by Apple Intelligence" : "Written on this iPhone"
        } else if written > 0 {
            source = "Written on this iPhone by Apple Intelligence. \(input.parts.count - written) of \(input.parts.count) items use the meeting's key points instead."
        } else {
            source = "Written on this iPhone from the meeting's key points (Apple Intelligence wasn't available)"
        }
        return Draft(text: document(input, items: items), source: source)
    }

    /// For a part Apple Intelligence couldn't write: the topic's key points, or rule-based ones.
    private static func basicItem(for part: Part, isOnlyPart: Bool, speakers: [Speaker]) async -> Item {
        var points = part.keyPoints
        if points.isEmpty, let basic = try? await HeuristicEnhancer().enhance(segments: part.segments, speakers: speakers, userNotes: "") {
            points = NotesText.bullets(from: basic.summary)
        }
        return Item(title: part.title ?? (isOnlyPart ? "Discussion" : "Discussion (\(part.start.clockString))"), points: Array(points.prefix(6)))
    }

    // MARK: - The document

    static func document(_ input: Input, items: [Item], locale: Locale = .current) -> String {
        var lines: [String] = [input.title, heldLine(start: input.start, duration: input.duration, locale: locale), ""]
        if let present = presentLine(names: input.present, unnamed: input.unnamedSpeakers) {
            lines += [present, ""]
        }

        var decisionsByItem: [Int: [String]] = [:]
        var otherDecisions: [String] = []
        for decision in input.decisions {
            if let index = itemIndex(for: decision.time, in: input.parts), index < items.count {
                decisionsByItem[index, default: []].append(decision.text)
            } else {
                otherDecisions.append(decision.text)
            }
        }
        var actionsByItem: [Int: [Action]] = [:]
        var otherActions: [Action] = []
        for action in input.actions {
            if let index = itemIndex(for: action.time, in: input.parts), index < items.count {
                actionsByItem[index, default: []].append(action)
            } else {
                otherActions.append(action)
            }
        }

        for (index, item) in items.enumerated() {
            let number = index + 1
            lines.append("\(number). \(item.title)")
            for (pointIndex, point) in item.points.enumerated() {
                lines.append("\(number).\(pointIndex + 1) \(sentence(point))")
            }
            lines += (decisionsByItem[index] ?? []).map { "Agreed: \(sentence($0))" }
            lines += (actionsByItem[index] ?? []).map { "Action: \(actionText($0))" }
            lines.append("")
        }

        if !otherDecisions.isEmpty || !otherActions.isEmpty {
            lines.append("\(items.count + 1). \(items.isEmpty ? "Decisions and actions" : "Other decisions and actions")")
            lines += otherDecisions.map { "Agreed: \(sentence($0))" }
            lines += otherActions.map { "Action: \(actionText($0))" }
            lines.append("")
        }

        if !input.actions.isEmpty {
            lines.append("Summary of actions")
            for (index, action) in input.actions.enumerated() {
                lines.append("A\(index + 1). \(actionText(action))\(action.isDone ? " (done)" : "")")
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "Minutes of the meeting held on Tuesday 3 November 2026, 10:00 to 10:45"
    static func heldLine(start: Date, duration: TimeInterval, locale: Locale = .current) -> String {
        let day = DateFormatter()
        day.locale = locale
        day.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        let time = DateFormatter()
        time.locale = locale
        time.dateStyle = .none
        time.timeStyle = .short
        let end = start.addingTimeInterval(duration)
        return "Minutes of the meeting held on \(day.string(from: start)), \(time.string(from: start)) to \(time.string(from: end))"
    }

    /// "Present: Priya Sharma, Tom Ellis and 1 other", or nil when no voices were separated.
    static func presentLine(names: [String], unnamed: Int) -> String? {
        if names.isEmpty {
            guard unnamed > 0 else { return nil }
            return "Present: \(unnamed) \(unnamed == 1 ? "person" : "people") (speakers not named yet)"
        }
        var people = names
        if unnamed > 0 { people.append("\(unnamed) other\(unnamed == 1 ? "" : "s")") }
        return "Present: " + listText(people)
    }

    /// "A", "A and B", "A, B and C"
    static func listText(_ items: [String]) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " and " + last
    }

    /// The item an agreed point or action belongs under: the part of the meeting where it was said.
    /// With one part everything belongs to it; otherwise nil when it can't be placed.
    static func itemIndex(for time: TimeInterval?, in parts: [Part]) -> Int? {
        if parts.count == 1 { return 0 }
        guard let time, !parts.isEmpty else { return nil }
        return parts.lastIndex { $0.start <= time } ?? 0
    }

    /// "Share the new rota — Priya Sharma, by Friday"
    static func actionText(_ action: Action) -> String {
        let details = [action.owner, action.due].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let text = action.text.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return details.isEmpty ? text : "\(text) — \(details.joined(separator: ", "))"
    }

    /// Capitalised and ending in a full stop, as minutes are written.
    static func sentence(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = result.first else { return result }
        result = first.uppercased() + result.dropFirst()
        if let last = result.last, !".!?".contains(last) { result += "." }
        return result
    }

    // MARK: - Reading the model's answer

    /// The heading (when one was asked for) and the points, from the model's plain-text answer.
    static func parse(_ text: String, wantsTitle: Bool) -> (title: String?, points: [String]) {
        // Line breaks from any HTML first, so list items stay separate when the tags are removed.
        let broken = text
            .replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n- ", options: .regularExpression)
            .replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</h\\d>", with: "\n", options: .regularExpression)
        var lines = NotesText.plain(broken)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var title: String?
        if wantsTitle, let first = lines.first, !isBullet(first) {
            title = cleanTitle(first)
            lines.removeFirst()
        }
        let points = NotesText.bullets(from: lines.joined(separator: "\n"))
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "*_ ")) }
            .filter { $0.split(separator: " ").count >= 2 && !$0.hasSuffix(":") }
        return (title?.isEmpty == false ? title : nil, points)
    }

    private static func isBullet(_ line: String) -> Bool {
        line.hasPrefix("-") || line.hasPrefix("•") || line.hasPrefix("* ")
            || line.range(of: #"^\d+[.)]\s"#, options: .regularExpression) != nil
    }

    /// "**Heading: Rota changes**" → "Rota changes"
    private static func cleanTitle(_ line: String) -> String {
        var title = line.trimmingCharacters(in: CharacterSet(charactersIn: "#*_\"' "))
        for prefix in ["heading:", "title:", "topic:"] where title.lowercased().hasPrefix(prefix) {
            title = String(title.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "#*_\"' "))
        }
        if title.hasSuffix(":") || title.hasSuffix(".") { title.removeLast() }
        return title
    }
}

extension MinutesWriter.Input {
    /// Copies what the minutes need from a meeting. Each topic becomes an item; a meeting without
    /// topics is one item.
    @MainActor
    init(_ meeting: Meeting) {
        let labels = Dictionary(uniqueKeysWithValues: meeting.speakers.map { ($0.id, $0.displayName) })
        let segments = meeting.segments
        func transcript(_ lines: [TranscriptSegment]) -> String {
            lines.map { segment in
                let speaker = segment.speakerID.flatMap { labels[$0] } ?? "Unknown"
                return "[\(segment.start.clockString)] \(speaker): \(segment.text)"
            }.joined(separator: "\n")
        }

        var parts: [MinutesWriter.Part] = []
        let topics = meeting.topics.sorted { $0.start < $1.start }
        if topics.count > 1 {
            for (index, topic) in topics.enumerated() {
                let isFirst = index == 0
                let next = index + 1 < topics.count ? topics[index + 1].start : .infinity
                let lines = segments.filter { (isFirst || $0.start >= topic.start) && $0.start < next }
                guard !lines.isEmpty else { continue }
                let title = topic.title.trimmingCharacters(in: .whitespaces)
                parts.append(MinutesWriter.Part(
                    title: title.isEmpty ? nil : title,
                    start: lines.first?.start ?? topic.start,
                    end: lines.last?.end ?? topic.end,
                    transcript: transcript(lines),
                    segments: lines,
                    keyPoints: topic.points
                ))
            }
        } else if !segments.isEmpty {
            parts.append(MinutesWriter.Part(
                title: topics.first.map(\.title).flatMap { $0.isEmpty ? nil : $0 },
                start: segments.first?.start ?? 0,
                end: segments.last?.end ?? meeting.duration,
                transcript: transcript(segments),
                segments: segments,
                keyPoints: NotesText.bullets(from: meeting.summary)
            ))
        }

        let speakers = meeting.speakers.sorted { $0.number < $1.number }
        var names: [String] = []
        for name in speakers.compactMap(\.name) where !names.contains(name) {
            names.append(name)
        }
        let startTimes = Dictionary(segments.map { ($0.id, $0.start) }, uniquingKeysWith: { first, _ in first })

        self.init(
            title: meeting.title,
            start: meeting.createdAt,
            duration: meeting.duration,
            present: names,
            unnamedSpeakers: speakers.filter { $0.name == nil }.count,
            parts: parts,
            decisions: meeting.decisions.map { MinutesWriter.Decision(text: $0, time: segments.segment(matching: $0)?.start) },
            actions: meeting.actions
                .filter { $0.status == .open || $0.status == .done }
                .sorted { $0.createdAt < $1.createdAt }
                .map { action in
                    MinutesWriter.Action(
                        text: action.text,
                        owner: action.owner,
                        due: action.due,
                        isDone: action.status == .done,
                        time: action.sourceSegmentID.flatMap { startTimes[$0] }
                    )
                },
            speakers: meeting.speakers
        )
    }
}

#if canImport(FoundationModels)
/// Writes one item of the minutes with the on-device model, in Apple's mode for transforming text
/// the user supplies (a transcript), which declines far less than its default mode.
@available(iOS 26.0, *)
private enum AIMinutes {
    struct EmptyAnswer: Error {}

    static let instructions = """
        You are an experienced minute-taker writing the formal minutes of a work meeting from its transcript. \
        Write in British English, in the third person and the past tense, using reported speech, for example \
        "Priya reported that the new rota was ready" or "Concerns were raised about weekend cover". \
        Record the substance: what was discussed, the views given and the conclusions reached, not every remark. \
        Name a person only when the transcript gives their name. For speakers labelled like "Speaker 2" or \
        "Unknown", write "It was noted that…" or "A member of the group said…" instead. Leave out small talk. \
        Only include what is in the transcript. Never invent names, figures or dates.
        """
    /// Roughly 1,200 tokens of transcript per request, leaving room for the answer.
    static let characterLimit = 4_500

    static func item(for part: MinutesWriter.Part) async throws -> MinutesWriter.Item {
        var title = part.title
        var points: [String] = []
        for piece in pieces(of: part.transcript) {
            let wantsTitle = title == nil
            let answer = try await write(piece, wantsTitle: wantsTitle)
            if wantsTitle { title = answer.title }
            points += answer.points
        }
        guard !points.isEmpty else { throw EmptyAnswer() }
        return MinutesWriter.Item(title: title ?? "Discussion", points: points)
    }

    private static func write(_ transcript: String, wantsTitle: Bool) async throws -> (title: String?, points: [String]) {
        let most = min(6, max(2, transcript.count / 700))
        var prompt = "Write the minutes for this part of the meeting."
        if wantsTitle {
            prompt += " On the first line write a heading of two to six words for what it was about, with no bullet."
        }
        prompt += " Write up to \(most) points, one per line, each starting with \"- \". Plain text only: no Markdown or HTML."
        prompt += "\n\nTranscript:\n\(transcript)"
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let text = try await AppleIntelligenceEnhancer.withRetries {
            let session = LanguageModelSession(model: model, instructions: instructions)
            return try await session.respond(to: prompt).content
        }
        return MinutesWriter.parse(text, wantsTitle: wantsTitle)
    }

    /// Splits a long part at line breaks into pieces the model can read.
    private static func pieces(of transcript: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in transcript.split(separator: "\n", omittingEmptySubsequences: true) {
            if !current.isEmpty, current.count + line.count + 1 > characterLimit {
                pieces.append(current)
                current = ""
            }
            current += (current.isEmpty ? "" : "\n") + line
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
#endif

/// Minutes being written, so the Minutes tab shows progress even after the user leaves and comes
/// back, and the same minutes aren't written twice at once.
@MainActor
@Observable
final class MinutesJobs {
    struct Progress: Equatable {
        var part: Int
        var of: Int
    }

    static let shared = MinutesJobs()

    private(set) var jobs: [PersistentIdentifier: Progress] = [:]

    func progress(for meeting: Meeting) -> Progress? {
        jobs[meeting.persistentModelID]
    }

    func write(_ meeting: Meeting) {
        let id = meeting.persistentModelID
        guard jobs[id] == nil else { return }
        let input = MinutesWriter.Input(meeting)
        jobs[id] = Progress(part: 0, of: max(1, input.parts.count))
        Task {
            let backgroundTime = BackgroundTime(name: "Write minutes")
            defer { backgroundTime.end() }
            let draft = await MinutesWriter.write(input) { part, total in
                self.jobs[id] = Progress(part: part, of: total)
            }
            meeting.minutes = draft.text
            meeting.minutesSource = draft.source
            meeting.minutesWrittenAt = .now
            try? meeting.modelContext?.save()
            jobs[id] = nil
        }
    }
}

/// The kinds of line in written minutes, for styling them.
enum MinutesLine: Equatable {
    case title(String)
    case subtitle(String)
    /// "Present: …"
    case labelled(label: String, text: String)
    /// "1. Rota changes"
    case heading(number: String, text: String)
    /// "1.2 Priya reported that…"
    case point(number: String, text: String)
    case agreed(String)
    case action(String)
    /// "Summary of actions"
    case section(String)
    /// "A1. Share the rota — Priya Sharma"
    case summaryAction(number: String, text: String)
    case paragraph(String)
}

enum MinutesFormat {
    static func lines(from text: String) -> [MinutesLine] {
        let raw = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return raw.enumerated().map { index, line in
            if index == 0 { return .title(line) }
            if line.hasPrefix("Minutes of ") { return .subtitle(line) }
            if let match = capture(#"^(\d+\.\d+)\s+(.+)$"#, in: line) { return .point(number: match.0, text: match.1) }
            if let match = capture(#"^(\d+)\.\s+(.+)$"#, in: line) { return .heading(number: match.0, text: match.1) }
            if let match = capture(#"^(A\d+)\.\s+(.+)$"#, in: line) { return .summaryAction(number: match.0, text: match.1) }
            if let rest = after("Agreed:", in: line) { return .agreed(rest) }
            if let rest = after("Action:", in: line) { return .action(rest) }
            if line.caseInsensitiveCompare("Summary of actions") == .orderedSame { return .section(line) }
            for label in ["Present", "Apologies", "In attendance", "Chair", "Minutes taken by", "Date of next meeting"] {
                if let rest = after("\(label):", in: line) { return .labelled(label: label, text: rest) }
            }
            return .paragraph(line)
        }
    }

    private static func after(_ prefix: String, in line: String) -> String? {
        guard line.lowercased().hasPrefix(prefix.lowercased()) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    private static func capture(_ pattern: String, in line: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              match.numberOfRanges == 3,
              let first = Range(match.range(at: 1), in: line),
              let second = Range(match.range(at: 2), in: line)
        else { return nil }
        return (String(line[first]), String(line[second]))
    }
}
