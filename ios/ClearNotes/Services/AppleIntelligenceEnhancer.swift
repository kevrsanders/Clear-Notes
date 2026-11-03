#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct GeneratedAction {
    @Guide(description: "The task, starting with a verb, e.g. 'Send the revised budget to finance'")
    var task: String
    @Guide(description: "The name of the person responsible, or an empty string if nobody was named. Never use a label like 'Speaker 2'.")
    var owner: String
    @Guide(description: "The deadline exactly as it was said, e.g. 'by Friday', or an empty string if none was given")
    var due: String
    @Guide(description: "A short quote, copied word for word from the transcript, where this action was agreed")
    var quote: String
}

@available(iOS 26.0, *)
@Generable
struct ChunkInsights {
    @Guide(description: "A title of two to five words for what this part of the meeting was mostly about, e.g. 'Launch timing'")
    var topic: String
    @Guide(description: "Up to six main points discussed, each a short sentence")
    var keyPoints: [String]
    @Guide(description: "Decisions that were clearly agreed. Leave empty if none.")
    var decisions: [String]
    @Guide(description: "Tasks someone committed to or was asked to do. Leave empty if none.")
    var actions: [GeneratedAction]
}

@available(iOS 26.0, *)
@Generable
struct MeetingOverview {
    @Guide(description: "A short, specific meeting title of at most six words")
    var title: String
    @Guide(description: "A summary of the meeting in three to five bullet points, each starting with '- '")
    var summary: String
}

/// Uses the on-device Apple Intelligence model. Nothing leaves the iPhone.
///
/// The on-device model has a small context window, so long transcripts are processed in parts
/// and the results merged. A part that fails doesn't lose the meeting: one that's too long is
/// split in two, and one the model declines (for example Apple's safety filter on a security
/// discussion) gets basic extraction instead. When the system is busy it waits and retries.
@available(iOS 26.0, *)
struct AppleIntelligenceEnhancer: NotesEnhancer {
    let sourceName = "Apple Intelligence (on this iPhone)"

    /// Roughly 1,200 tokens of transcript per part, leaving room for instructions and output.
    private let chunkCharacterLimit = 4_500
    /// The user's notes go into every part's prompt, so only the start of long notes is used.
    private let notesCharacterLimit = 1_200
    /// Key points sent for the overall summary, so a long meeting doesn't overflow the model.
    private let overviewCharacterLimit = 3_000
    /// Waits before retrying when Apple Intelligence is busy (rate limited).
    private static let busyRetryDelays: [Duration] = [.seconds(3), .seconds(8), .seconds(20)]

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { return true }
        return false
    }

    private static let instructions = """
        You help people turn meeting transcripts into clear notes. \
        Only include points, decisions and actions that are actually stated in the transcript. \
        Each transcript line starts with a time and the speaker. When someone says "I will" or "I'll", \
        they are the owner of that action. Never invent names, dates or tasks. Write in plain British English.
        """

    /// Why Apple Intelligence couldn't handle something, worded to follow "because".
    static func reason(for error: Error) -> String {
        if (error as? NotesEnhancerError) == .busy { return "Apple Intelligence was busy" }
        guard let error = error as? LanguageModelSession.GenerationError else { return error.localizedDescription }
        switch error {
        case .guardrailViolation: return "Apple's safety filter declined part of the conversation"
        case .exceededContextWindowSize: return "part of the meeting was too long for the model"
        case .rateLimited: return "Apple Intelligence was busy"
        case .assetsUnavailable: return "Apple Intelligence wasn't ready on this iPhone"
        case .unsupportedLanguageOrLocale: return "the language isn't supported"
        case .decodingFailure, .unsupportedGuide: return "the model's answer couldn't be read"
        default: return error.localizedDescription
        }
    }

    func enhance(segments: [TranscriptSegment], speakers: [Speaker], userNotes: String) async throws -> MeetingInsights {
        let labels = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.displayName) })
        let notes = String(userNotes.prefix(notesCharacterLimit))

        var parts: [PartResult] = []
        for chunk in chunks(of: segments, labels: labels) {
            parts += try await extract(chunk, notes: notes, speakers: speakers, labels: labels, allowSplit: true)
        }

        let decisions = parts.flatMap(\.decisions)
        let actions = parts.flatMap(\.actions)
        let topics = parts.map { Topic(title: $0.topic, start: $0.start, end: $0.end, points: Array($0.keyPoints.prefix(3))) }
        var reasons: [String] = []
        for part in parts {
            if let reason = part.basicReason, !reasons.contains(reason) { reasons.append(reason) }
        }

        let points = overviewPoints(parts.map(\.keyPoints))
        var title: String?
        var summary: String
        if points.isEmpty {
            summary = "Nothing substantial was discussed."
        } else {
            do {
                let overview = try await generate(
                    "Write a title and summary for a meeting with these key points:\n" + points.map { "- \($0)" }.joined(separator: "\n"),
                    as: MeetingOverview.self
                )
                title = overview.title
                summary = overview.summary
            } catch let error as NotesEnhancerError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                summary = points.prefix(5).map { "- \($0)" }.joined(separator: "\n")
                let reason = Self.reason(for: error)
                if !reasons.contains(reason) { reasons.append(reason) }
            }
        }

        let basicParts = parts.filter { $0.basicReason != nil }.count
        var note: String?
        if basicParts == parts.count, !parts.isEmpty {
            note = "Apple Intelligence couldn't write these notes because \(reasons.joined(separator: " and ")), so basic extraction was used."
        } else if basicParts > 0 {
            note = "Apple Intelligence wrote most of these notes. \(basicParts) of \(parts.count) parts use basic extraction because \(reasons.joined(separator: " and "))."
        } else if !reasons.isEmpty {
            note = "The summary is a list of key points because \(reasons.joined(separator: " and "))."
        }

        return MeetingInsights(
            title: title,
            summary: summary,
            decisions: decisions,
            actions: actions,
            // One part covers the whole meeting, so topics would only repeat the summary.
            topics: topics.count > 1 ? topics.filter { !$0.title.isEmpty } : [],
            note: note
        )
    }

    // MARK: - Parts

    private struct Chunk {
        var segments: [TranscriptSegment]
        var text: String
        var start: TimeInterval { segments.first?.start ?? 0 }
        var end: TimeInterval { segments.last?.end ?? 0 }

        init(segments: [TranscriptSegment], labels: [String: String]) {
            self.segments = segments
            text = segments.map { segment in
                let speaker = segment.speakerID.flatMap { labels[$0] } ?? "Unknown"
                return "[\(segment.start.clockString)] \(speaker): \(segment.text)\n"
            }.joined()
        }
    }

    private struct PartResult {
        var topic: String
        var keyPoints: [String]
        var decisions: [String]
        var actions: [ExtractedAction]
        var start: TimeInterval
        var end: TimeInterval
        /// Set when this part used basic extraction, saying why.
        var basicReason: String?
    }

    /// Splits the transcript into parts small enough for the model. Each part becomes a topic.
    private func chunks(of segments: [TranscriptSegment], labels: [String: String]) -> [Chunk] {
        var groups: [[TranscriptSegment]] = []
        var current: [TranscriptSegment] = []
        var length = 0
        for segment in segments {
            let lineLength = segment.text.count + 24
            if !current.isEmpty, length + lineLength > chunkCharacterLimit {
                groups.append(current)
                current = []
                length = 0
            }
            current.append(segment)
            length += lineLength
        }
        if !current.isEmpty { groups.append(current) }
        return groups.map { Chunk(segments: $0, labels: labels) }
    }

    private func extract(
        _ chunk: Chunk,
        notes: String,
        speakers: [Speaker],
        labels: [String: String],
        allowSplit: Bool
    ) async throws -> [PartResult] {
        var prompt = "Extract the key points, decisions and actions from this part of a meeting transcript.\n\n"
        if !notes.isEmpty {
            prompt += "The note-taker wrote these notes, which show what they thought mattered:\n\(notes)\n\n"
        }
        prompt += "Transcript:\n\(chunk.text)"

        do {
            let result = try await generate(prompt, as: ChunkInsights.self)
            return [PartResult(
                topic: result.topic.trimmingCharacters(in: .whitespacesAndNewlines),
                keyPoints: result.keyPoints,
                decisions: result.decisions,
                actions: result.actions.map {
                    ExtractedAction(
                        task: $0.task,
                        owner: $0.owner.isEmpty ? nil : $0.owner,
                        due: $0.due.isEmpty ? nil : $0.due,
                        evidence: $0.quote
                    )
                },
                start: chunk.start,
                end: chunk.end
            )]
        } catch let error as NotesEnhancerError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if case .exceededContextWindowSize? = error as? LanguageModelSession.GenerationError,
               allowSplit, chunk.segments.count > 1 {
                let middle = chunk.segments.count / 2
                let first = Chunk(segments: Array(chunk.segments[..<middle]), labels: labels)
                let second = Chunk(segments: Array(chunk.segments[middle...]), labels: labels)
                let firstResults = try await extract(first, notes: notes, speakers: speakers, labels: labels, allowSplit: false)
                let secondResults = try await extract(second, notes: notes, speakers: speakers, labels: labels, allowSplit: false)
                return firstResults + secondResults
            }
            return [try await basicPart(chunk, speakers: speakers, reason: Self.reason(for: error))]
        }
    }

    /// Rule-based extraction for one part the model couldn't handle.
    private func basicPart(_ chunk: Chunk, speakers: [Speaker], reason: String) async throws -> PartResult {
        let basic = try await HeuristicEnhancer().enhance(segments: chunk.segments, speakers: speakers, userNotes: "")
        let points = basic.summary
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
        return PartResult(
            topic: "",
            keyPoints: points,
            decisions: basic.decisions,
            actions: basic.actions,
            start: chunk.start,
            end: chunk.end,
            basicReason: reason
        )
    }

    /// Key points for the summary, taking each part's first point, then each part's second, and so
    /// on, so every part of the meeting is represented within the limit.
    private func overviewPoints(_ pointsByPart: [[String]]) -> [String] {
        var chosen: [String] = []
        var length = 0
        let deepest = pointsByPart.map(\.count).max() ?? 0
        for rank in 0..<deepest {
            for points in pointsByPart where rank < points.count {
                let point = points[rank]
                guard length + point.count <= overviewCharacterLimit else { return chosen }
                chosen.append(point)
                length += point.count + 3
            }
        }
        return chosen
    }

    /// One request to the model, retried with growing waits while the system is busy.
    private func generate<Content: Generable>(_ prompt: String, as type: Content.Type) async throws -> Content {
        var attempt = 0
        while true {
            do {
                let session = LanguageModelSession(instructions: Self.instructions)
                return try await session.respond(to: prompt, generating: type).content
            } catch let error as LanguageModelSession.GenerationError {
                guard case .rateLimited = error else { throw error }
                guard attempt < Self.busyRetryDelays.count else { throw NotesEnhancerError.busy }
                try await Task.sleep(for: Self.busyRetryDelays[attempt])
                attempt += 1
            }
        }
    }
}
#endif
