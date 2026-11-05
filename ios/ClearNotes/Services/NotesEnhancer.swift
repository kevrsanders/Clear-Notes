import CryptoKit
import Foundation

struct ExtractedAction: Codable, Equatable, Sendable {
    var task: String
    var owner: String?
    var due: String?
    /// A short quote from the transcript supporting the action, used to link back to the source.
    var evidence: String?
    /// Set when the user marked this action while recording.
    var markID: UUID?
}

struct MeetingInsights: Equatable, Sendable {
    var title: String?
    var summary: String
    var decisions: [String]
    var actions: [ExtractedAction]
    var topics: [Topic] = []
    /// Shown with the notes when part of them couldn't be written as usual, saying why.
    var note: String?
}

enum NotesEnhancerError: Error, Equatable, LocalizedError {
    /// Apple Intelligence kept refusing requests because too many were made (it limits apps in
    /// the background most). The meeting finishes when Clear Notes is next open.
    case busy

    var errorDescription: String? {
        "Apple Intelligence is busy. The notes will finish when Clear Notes is open."
    }
}

/// Turns a transcript and the user's own notes into a summary, decisions and suggested actions.
protocol NotesEnhancer: Sendable {
    var sourceName: String { get }
    func enhance(segments: [TranscriptSegment], speakers: [Speaker], userNotes: String) async throws -> MeetingInsights
    /// The same, saving each finished part of a long meeting to `progress` so the notes carry on
    /// where they stopped if iOS pauses Clear Notes, and reporting how far they've got.
    func enhance(
        segments: [TranscriptSegment],
        speakers: [Speaker],
        userNotes: String,
        progress: NotesProgress?
    ) async throws -> MeetingInsights
}

extension NotesEnhancer {
    /// Engines that finish quickly (rule-based extraction) don't need to save their progress.
    func enhance(
        segments: [TranscriptSegment],
        speakers: [Speaker],
        userNotes: String,
        progress: NotesProgress?
    ) async throws -> MeetingInsights {
        try await enhance(segments: segments, speakers: speakers, userNotes: userNotes)
    }
}

/// One finished part of a long meeting's notes: its topic, key points, decisions and actions.
struct NotesPart: Codable, Equatable, Sendable {
    var topic: String
    var keyPoints: [String]
    var decisions: [String]
    var actions: [ExtractedAction]
    var start: TimeInterval
    var end: TimeInterval
    /// Set when this part used basic extraction, saying why.
    var basicReason: String?
}

/// Where a notes engine saves finished parts and reports how far it has got.
protocol NotesProgress: Sendable {
    /// Parts already written for a piece of the transcript (see `NotesPartKey`), if any.
    func savedParts(for key: String) async -> [NotesPart]?
    func save(_ parts: [NotesPart], for key: String) async
    /// `done` of `total` parts are written. Called before the first part and after each one.
    func update(done: Int, of total: Int) async
}

/// Identifies a piece of the transcript, so a saved part is reused only for exactly the same text
/// (and the same notes from the user). Stable across launches, unlike `hashValue`.
enum NotesPartKey {
    static func make(transcript: String, notes: String) -> String {
        let digest = SHA256.hash(data: Data((notes + "\u{1F}" + transcript).utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }
}

/// Writes a long meeting's notes one piece of transcript at a time. A piece already written (saved
/// under its key) is reused, and each new one is saved as soon as it's written, so the notes carry
/// on where they stopped after a pause.
enum PartByPart {
    static func run(
        _ pieces: [String],
        notes: String,
        progress: NotesProgress?,
        write: (Int) async throws -> [NotesPart]
    ) async throws -> [NotesPart] {
        var parts: [NotesPart] = []
        await progress?.update(done: 0, of: pieces.count)
        for (index, piece) in pieces.enumerated() {
            let key = NotesPartKey.make(transcript: piece, notes: notes)
            if let saved = await progress?.savedParts(for: key) {
                parts += saved
            } else {
                let written = try await write(index)
                await progress?.save(written, for: key)
                parts += written
            }
            await progress?.update(done: index + 1, of: pieces.count)
        }
        return parts
    }
}

/// Saved parts, stored on the meeting as JSON until its notes are finished.
enum NotesCheckpoint {
    static func decode(_ data: Data?) -> [String: [NotesPart]] {
        guard let data, let parts = try? JSONDecoder().decode([String: [NotesPart]].self, from: data) else { return [:] }
        return parts
    }

    static func encode(_ parts: [String: [NotesPart]]) -> Data? {
        parts.isEmpty ? nil : try? JSONEncoder().encode(parts)
    }
}

/// How far a meeting's processing has got, for the processing card and the system's progress view.
enum ProcessingProgress {
    /// Improving the transcript and identifying speakers take roughly the first half; writing the
    /// notes, part by part, the second.
    static func fraction(stage: ProcessingStage?, partsDone: Int, partsTotal: Int) -> Double {
        switch stage {
        case nil: 0.1
        case .transcript: 0.2
        case .speakers: 0.4
        case .notes:
            partsTotal > 0 ? 0.55 + 0.4 * Double(min(partsDone, partsTotal)) / Double(partsTotal) : 0.55
        }
    }

    /// "Part 12 of 38" while a long meeting's notes are written, then "Writing the summary".
    static func notesDetail(partsDone: Int, partsTotal: Int) -> String? {
        guard partsTotal > 1 else { return nil }
        return partsDone >= partsTotal ? "Writing the summary" : "Part \(partsDone + 1) of \(partsTotal)"
    }

    /// One line for the system's progress view, e.g. "Writing notes · part 12 of 38".
    static func subtitle(stage: ProcessingStage?, partsDone: Int, partsTotal: Int) -> String {
        switch stage {
        case .transcript:
            return "Improving the transcript"
        case .speakers:
            return "Identifying speakers"
        case .notes:
            guard partsTotal > 1 else { return "Writing notes" }
            return partsDone >= partsTotal ? "Writing the summary" : "Writing notes · part \(partsDone + 1) of \(partsTotal)"
        case nil:
            return "Starting"
        }
    }
}

enum NotesEnhancers {
    /// Apple Intelligence when this iPhone supports it, otherwise basic rule-based extraction.
    /// Both run entirely on the device.
    static func best() -> NotesEnhancer {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceEnhancer.isAvailable {
            return AppleIntelligenceEnhancer()
        }
        #endif
        return HeuristicEnhancer()
    }

    /// Why notes couldn't be written, worded to follow "because".
    static func reason(for error: Error) -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceEnhancer.reason(for: error)
        }
        #endif
        return error.localizedDescription
    }

    static var isAppleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return AppleIntelligenceEnhancer.isAvailable
        }
        #endif
        return false
    }
}

/// Tidies text from the language model, which sometimes answers in HTML or other bullet styles.
enum NotesText {
    /// Bullet points from "- " lines, "•" or "*" bullets, numbered lines or HTML list items.
    static func bullets(from text: String) -> [String] {
        var source = text.replacingOccurrences(of: "(?i)<li[^>]*>", with: "\n", options: .regularExpression)
        source = source.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        return plain(source)
            .split(whereSeparator: \.isNewline)
            .flatMap { splitRunTogether(String($0)) }
            .map { line -> String in
                var item = line.trimmingCharacters(in: .whitespaces)
                while let first = item.first, "-•*–".contains(first) {
                    item = String(item.dropFirst()).trimmingCharacters(in: .whitespaces)
                }
                if let number = item.range(of: #"^\d+[.)]\s+"#, options: .regularExpression) {
                    item.removeSubrange(number)
                }
                return item
            }
            .filter { !$0.isEmpty }
    }

    /// Points the model ran together on one line, e.g. "Budget agreed. - Rota ready." becomes two.
    /// Only a dash or bullet straight after the end of a sentence counts, so "Wi-Fi" and "10 - 12" stay.
    static func splitRunTogether(_ line: String) -> [String] {
        line.replacingOccurrences(of: #"(?<=[.!?])\s+[-•–]\s+"#, with: "\n", options: .regularExpression)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The same text as "- " bullet lines, the format the notes use.
    static func bulletList(_ text: String) -> String {
        bullets(from: text).map { "- \($0)" }.joined(separator: "\n")
    }

    /// Removes HTML tags and decodes the common entities.
    static func plain(_ text: String) -> String {
        var result = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        let entities = [("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&nbsp;", " "), ("&amp;", "&")]
        for (entity, character) in entities {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Keeps one of each action when several parts of a meeting suggest the same thing.
enum ActionList {
    /// Two actions are the same when most of their words match and they aren't for different people.
    static func deduplicated(_ actions: [ExtractedAction]) -> [ExtractedAction] {
        var kept: [(action: ExtractedAction, words: Set<String>)] = []
        for action in actions {
            let words = significantWords(action.task)
            guard !words.isEmpty else { continue }
            let repeatsOne = kept.contains { other in
                let overlap = Double(words.intersection(other.words).count) / Double(words.union(other.words).count)
                return overlap >= 0.6 && sameOrUnknownOwner(action.owner, other.action.owner)
            }
            if !repeatsOne {
                kept.append((action, words))
            }
        }
        return kept.map { $0.action }
    }

    /// Mostly the same words, e.g. an action that repeats a decision.
    static func similar(_ first: String, _ second: String) -> Bool {
        let firstWords = significantWords(first)
        let secondWords = significantWords(second)
        guard !firstWords.isEmpty, !secondWords.isEmpty else { return false }
        return Double(firstWords.intersection(secondWords).count) / Double(firstWords.union(secondWords).count) >= 0.6
    }

    private static func sameOrUnknownOwner(_ first: String?, _ second: String?) -> Bool {
        guard let first, let second else { return true }
        return first.caseInsensitiveCompare(second) == .orderedSame
    }

    private static func significantWords(_ text: String) -> Set<String> {
        Set(text.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 })
    }
}

extension Array where Element == TranscriptSegment {
    /// The segment whose text best contains the quote, for linking AI output back to the transcript.
    func segment(matching quote: String?) -> TranscriptSegment? {
        guard let quote = quote?.trimmingCharacters(in: .whitespacesAndNewlines), !quote.isEmpty else { return nil }
        let needle = quote.lowercased()
        if let exact = first(where: { $0.text.lowercased().contains(needle) }) {
            return exact
        }
        // Fall back to the segment that shares the most words with the quote.
        let words = Set(needle.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        guard !words.isEmpty else { return nil }
        let scored = map { segment -> (TranscriptSegment, Int) in
            let segmentWords = Set(segment.text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            return (segment, words.intersection(segmentWords).count)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 * 2 >= words.count else { return nil }
        return best.0
    }
}
