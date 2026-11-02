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
/// The on-device model has a small context window, so long transcripts are processed
/// in chunks and the results merged (map-reduce).
@available(iOS 26.0, *)
struct AppleIntelligenceEnhancer: NotesEnhancer {
    let sourceName = "Apple Intelligence (on this iPhone)"

    /// Roughly 1,200 tokens of transcript per chunk, leaving room for instructions and output.
    private let chunkCharacterLimit = 4_500

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

    func enhance(segments: [TranscriptSegment], speakers: [Speaker], userNotes: String) async throws -> MeetingInsights {
        let labels = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.displayName) })
        var keyPoints: [String] = []
        var decisions: [String] = []
        var actions: [ExtractedAction] = []
        var topics: [Topic] = []

        let parts = chunks(of: segments, labels: labels)
        for chunk in parts {
            let session = LanguageModelSession(instructions: Self.instructions)
            var prompt = "Extract the key points, decisions and actions from this part of a meeting transcript.\n\n"
            if !userNotes.isEmpty {
                prompt += "The note-taker wrote these notes, which show what they thought mattered:\n\(userNotes)\n\n"
            }
            prompt += "Transcript:\n\(chunk.text)"

            let result = try await session.respond(to: prompt, generating: ChunkInsights.self).content
            keyPoints += result.keyPoints
            decisions += result.decisions
            topics.append(Topic(
                title: result.topic.trimmingCharacters(in: .whitespacesAndNewlines),
                start: chunk.start,
                end: chunk.end,
                points: Array(result.keyPoints.prefix(3))
            ))
            actions += result.actions.map {
                ExtractedAction(
                    task: $0.task,
                    owner: $0.owner.isEmpty ? nil : $0.owner,
                    due: $0.due.isEmpty ? nil : $0.due,
                    evidence: $0.quote
                )
            }
        }

        guard !keyPoints.isEmpty else {
            return MeetingInsights(title: nil, summary: "Nothing substantial was discussed.", decisions: decisions, actions: actions)
        }

        let session = LanguageModelSession(instructions: Self.instructions)
        let overview = try await session.respond(
            to: "Write a title and summary for a meeting with these key points:\n" + keyPoints.map { "- \($0)" }.joined(separator: "\n"),
            generating: MeetingOverview.self
        ).content

        return MeetingInsights(
            title: overview.title,
            summary: overview.summary,
            decisions: decisions,
            actions: actions,
            // One part covers the whole meeting, so topics would only repeat the summary.
            topics: topics.count > 1 ? topics.filter { !$0.title.isEmpty } : []
        )
    }

    private struct Chunk {
        var text = ""
        var start: TimeInterval
        var end: TimeInterval
    }

    /// Splits the transcript into parts small enough for the model. Each part becomes a topic.
    private func chunks(of segments: [TranscriptSegment], labels: [String: String]) -> [Chunk] {
        var chunks: [Chunk] = []
        var current: Chunk?
        for segment in segments {
            let speaker = segment.speakerID.flatMap { labels[$0] } ?? "Unknown"
            let line = "[\(segment.start.clockString)] \(speaker): \(segment.text)\n"
            if let full = current, full.text.count + line.count > chunkCharacterLimit {
                chunks.append(full)
                current = nil
            }
            if current == nil {
                current = Chunk(start: segment.start, end: segment.end)
            }
            current?.text += line
            current?.end = segment.end
        }
        if let current { chunks.append(current) }
        return chunks
    }
}
#endif
