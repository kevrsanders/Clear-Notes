import Foundation

struct ExtractedAction: Equatable, Sendable {
    var task: String
    var owner: String?
    var due: String?
    /// A short quote from the transcript supporting the action, used to link back to the source.
    var evidence: String?
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
