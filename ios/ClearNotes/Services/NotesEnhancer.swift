import Foundation

struct ExtractedAction: Equatable, Sendable {
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
