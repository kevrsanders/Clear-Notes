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
    @Guide(description: "Decisions that were clearly agreed, each written as what was decided. Not tasks for a person. Leave empty if none.")
    var decisions: [String]
    @Guide(description: "At most three tasks that a person clearly promised to do ('I'll…') or was clearly asked to do ('Can you…'). Never a discussion point, idea, general need or decision. Most parts of a meeting have none: leave empty unless you're sure.")
    var actions: [GeneratedAction]
}

@available(iOS 26.0, *)
@Generable
struct MarkedActionText {
    @Guide(description: "The one task agreed just before the mark, starting with a verb, written so it makes sense on its own: replace 'it', 'that', 'this' and 'them' with what they refer to, e.g. 'Send the revised budget to finance'")
    var task: String
    @Guide(description: "The name of the person who will do it, or an empty string if nobody was named. Never a label like 'Speaker 2'.")
    var owner: String
    @Guide(description: "The deadline exactly as it was said, or an empty string if none was given")
    var due: String
    @Guide(description: "One short phrase of useful detail said in the excerpt: why it's needed, who it's for, or what it should include. An empty string if the excerpt gives none. Never invent anything.")
    var context: String
}

/// What a possible action turned out to be, once what was said around it is read.
@available(iOS 26.0, *)
@Generable
enum ActionVerdict {
    case promise
    case acceptedRequest
    case passedToSomeoneElse
    case declined
    case ideaOrSuggestion
    case alreadyDone
    case decision
    case notATask
}

@available(iOS 26.0, *)
@Generable
struct CheckedAction {
    @Guide(description: "What the >> line really is, judged from what was said before and after it. promise: the speaker says they will do something. acceptedRequest: someone is asked to do something and agrees, or goes along with it. passedToSomeoneElse: it's said that a different, named person will do it. declined: they say no. ideaOrSuggestion: 'we should', 'it would be good to', 'maybe', with nobody taking it on. alreadyDone: it has already been done. decision: something the group agreed, not a task for one person. notATask: anything else.")
    var verdict: ActionVerdict
    @Guide(description: "The task, starting with a verb, written so it makes sense on its own: replace 'it', 'that', 'this' and 'them' with what they refer to in the excerpt, e.g. 'Send the revised rota to the ward managers'. An empty string if it isn't a task.")
    var task: String
    @Guide(description: "The name of the person who will do it, which isn't always the person speaking, or an empty string if nobody was named. Never a label like 'Speaker 2'.")
    var owner: String
    @Guide(description: "The deadline exactly as it was said, e.g. 'by Friday', or an empty string if none was given")
    var due: String
    @Guide(description: "One short phrase of useful detail said in the excerpt: why it's needed, who it's for, or what it should include, e.g. 'Priya needs it for Monday's planning meeting'. An empty string if the excerpt gives none. Never invent anything.")
    var context: String
}

@available(iOS 26.0, *)
@Generable
struct MarkedDecisionText {
    @Guide(description: "The one decision agreed just before the mark, written as what was decided")
    var decision: String
}

@available(iOS 26.0, *)
@Generable
struct MeetingOverview {
    @Guide(description: "A short, specific meeting title of at most six words")
    var title: String
    @Guide(description: "A summary of the meeting in three to five bullet points, one per line, each starting with '- '. Plain text only: no HTML or Markdown.")
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
    /// Most actions taken from each part, so a long meeting doesn't produce a hundred suggestions.
    static let actionsPerPart = 3
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
        they are the owner of that action. A decision is something the group agreed; an action is a task \
        a person will do. Never list the same thing as both. Never invent names, dates or tasks. \
        Write in plain British English.
        """

    /// Why Apple Intelligence couldn't handle something, worded to follow "because", with "it"
    /// meaning Apple Intelligence.
    static func reason(for error: Error) -> String {
        if (error as? NotesEnhancerError) == .busy { return "it was busy" }
        if isSafetyBlock(error) { return "Apple's safety filter declined part of the conversation" }
        guard let generationError = error as? LanguageModelSession.GenerationError else {
            // E.g. "FoundationModels.LanguageModelError error -1": a generic system error.
            let nsError = error as NSError
            let name = nsError.domain.split(separator: ".").last.map(String.init) ?? nsError.domain
            return "it hit an internal error on this iPhone (\(name) \(nsError.code))"
        }
        switch generationError {
        case .guardrailViolation: return "Apple's safety filter declined part of the conversation"
        case .exceededContextWindowSize: return "part of the meeting was too long for it"
        case .rateLimited: return "it was busy"
        case .assetsUnavailable: return "it wasn't ready on this iPhone"
        case .unsupportedLanguageOrLocale: return "the language isn't supported"
        case .decodingFailure, .unsupportedGuide: return "its answer couldn't be read"
        default: return "it couldn't answer (\(generationError.localizedDescription))"
        }
    }

    /// Apple's safety filter blocked the request. It reports this in more than one way, e.g. a
    /// guardrail violation or "Detected content likely to be unsafe".
    static func isSafetyBlock(_ error: Error) -> Bool {
        if case .guardrailViolation? = error as? LanguageModelSession.GenerationError { return true }
        let description = error.localizedDescription.lowercased()
        return description.contains("unsafe") || description.contains("guardrail") || description.contains("refus")
    }

    func enhance(segments: [TranscriptSegment], speakers: [Speaker], userNotes: String) async throws -> MeetingInsights {
        try await enhance(segments: segments, speakers: speakers, userNotes: userNotes, progress: nil)
    }

    func enhance(
        segments: [TranscriptSegment],
        speakers: [Speaker],
        userNotes: String,
        progress: NotesProgress?
    ) async throws -> MeetingInsights {
        let labels = Dictionary(uniqueKeysWithValues: speakers.map { ($0.id, $0.displayName) })
        let notes = String(userNotes.prefix(notesCharacterLimit))

        // Each part is saved as soon as it's written, so if iOS pauses Clear Notes part-way through
        // a long meeting, the notes carry on from the next part rather than starting again.
        let allChunks = chunks(of: segments, labels: labels)
        let parts = try await PartByPart.run(allChunks.map(\.text), notes: notes, progress: progress) { index in
            try await extract(allChunks[index], notes: notes, speakers: speakers, labels: labels, allowSplit: true)
        }

        let decisions = parts.flatMap(\.decisions)
        let actions = parts.flatMap(\.actions)
        // A meeting's page shows its topics, not a summary, so even a short meeting written in one
        // part has one, with a few more of its points.
        let pointsPerTopic = parts.count == 1 ? 5 : 3
        let topics = parts.map { Topic(title: $0.topic, start: $0.start, end: $0.end, points: Array($0.keyPoints.prefix(pointsPerTopic))) }
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
                title = NotesText.plain(overview.title)
                // The model sometimes answers in HTML (<ul><li>…) despite the instructions.
                summary = NotesText.bulletList(overview.summary)
            } catch let error as NotesEnhancerError {
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // In the background this is usually iOS limiting Clear Notes, so pause and write the
                // summary properly when the app is open, rather than settling for a list of points.
                if await !AppActivity.isActive { throw NotesEnhancerError.busy }
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
            topics: topics.filter { !$0.title.isEmpty },
            note: note
        )
    }

    // MARK: - Marked moments

    /// Writes the action agreed just before a mark, or nil if the model can't (the caller then
    /// uses rule-based extraction).
    func markedAction(excerpt: String, markedAt: String, spoken: Bool) async -> ExtractedAction? {
        let how = spoken ? "someone said an action phrase at \(markedAt)" : "the note-taker tapped Mark action at \(markedAt)"
        let prompt = "In this meeting excerpt, \(how), just after an action was agreed. Write that one action.\n\nExcerpt:\n\(excerpt)"
        guard let result = try? await generate(prompt, as: MarkedActionText.self) else { return nil }
        let task = NotesText.plain(result.task)
        guard !task.isEmpty else { return nil }
        return ExtractedAction(
            task: task,
            owner: result.owner.isEmpty ? nil : NotesText.plain(result.owner),
            due: result.due.isEmpty ? nil : NotesText.plain(result.due),
            context: Self.optionalText(result.context)
        )
    }

    /// Reads what was said around a possible action (the line marked ">>") and says what it really
    /// is, rewriting the task so it stands on its own. Nil if the model can't answer.
    func checkAction(excerpt: String, noted: String) async -> ActionCheck.Result? {
        let prompt = """
            The line starting with >> in this meeting excerpt was noted as a possible task: "\(noted)". \
            Read what was said before it and after it. Decide whether someone really took on a task, \
            and write it with the details the excerpt gives.

            Excerpt:
            \(excerpt)
            """
        guard let result = try? await generate(prompt, as: CheckedAction.self) else { return nil }
        let verdict: ActionCheck.Verdict = switch result.verdict {
        case .promise: .promise
        case .acceptedRequest: .acceptedRequest
        case .passedToSomeoneElse: .passedOn
        case .declined: .declined
        case .ideaOrSuggestion: .idea
        case .alreadyDone: .alreadyDone
        case .decision: .decision
        case .notATask: .notATask
        }
        return ActionCheck.Result(
            verdict: verdict,
            action: ExtractedAction(
                task: NotesText.plain(result.task),
                owner: Self.optionalText(result.owner),
                due: Self.optionalText(result.due),
                context: Self.optionalText(result.context)
            )
        )
    }

    /// Nil for an empty answer.
    private static func optionalText(_ text: String) -> String? {
        let plain = NotesText.plain(text)
        return plain.isEmpty ? nil : plain
    }

    /// Writes the decision agreed just before a mark, or nil if the model can't.
    func markedDecision(excerpt: String, markedAt: String, spoken: Bool) async -> String? {
        let how = spoken ? "someone said a decision phrase at \(markedAt)" : "the note-taker tapped Mark decision at \(markedAt)"
        let prompt = "In this meeting excerpt, \(how), just after a decision was agreed. Write that one decision.\n\nExcerpt:\n\(excerpt)"
        guard let result = try? await generate(prompt, as: MarkedDecisionText.self) else { return nil }
        let decision = NotesText.plain(result.decision)
        return decision.isEmpty ? nil : decision
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
    ) async throws -> [NotesPart] {
        var prompt = "Extract the key points, decisions and actions from this part of a meeting transcript.\n\n"
        if !notes.isEmpty {
            prompt += "The note-taker wrote these notes, which show what they thought mattered:\n\(notes)\n\n"
        }
        prompt += "Transcript:\n\(chunk.text)"

        do {
            let result = try await generate(prompt, as: ChunkInsights.self)
            return [NotesPart(
                topic: NotesText.plain(result.topic),
                keyPoints: result.keyPoints.map(NotesText.plain).filter { !$0.isEmpty },
                decisions: result.decisions.map(NotesText.plain).filter { !$0.isEmpty },
                actions: result.actions.prefix(Self.actionsPerPart).map {
                    ExtractedAction(
                        task: NotesText.plain($0.task),
                        owner: $0.owner.isEmpty ? nil : NotesText.plain($0.owner),
                        due: $0.due.isEmpty ? nil : NotesText.plain($0.due),
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
            // In the background a failure is usually iOS limiting Clear Notes rather than a problem
            // with this part, so pause instead of saving basic notes for it. Safety blocks are
            // the same whenever they're tried, so they're handled now.
            if !Self.isSafetyBlock(error), await !AppActivity.isActive {
                throw NotesEnhancerError.busy
            }
            if Self.isSafetyBlock(error), let points = try? await permissiveKeyPoints(for: chunk), !points.isEmpty {
                // Apple's summarising mode wrote the key points; rules find this part's decisions and actions.
                var part = try await basicPart(chunk, speakers: speakers, reason: nil)
                part.keyPoints = points
                return [part]
            }
            return [try await basicPart(chunk, speakers: speakers, reason: Self.reason(for: error))]
        }
    }

    /// For a part Apple's safety filter blocked. The filter can't be turned off, but Apple has a
    /// gentler mode for summarising text the user supplies, such as a meeting transcript. It only
    /// applies to plain-text answers, so this asks for plain bullet points rather than structured notes.
    private func permissiveKeyPoints(for chunk: Chunk) async throws -> [String] {
        let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
        let prompt = """
            Summarise this part of a work meeting transcript as up to six short bullet points, \
            one per line, each starting with "- ". Plain text only.

            Transcript:
            \(chunk.text)
            """
        let text = try await Self.withRetries {
            let session = LanguageModelSession(model: model, instructions: Self.instructions)
            return try await session.respond(to: prompt).content
        }
        return Array(NotesText.bullets(from: text).prefix(6))
    }

    /// Rule-based extraction for one part the model couldn't handle.
    private func basicPart(_ chunk: Chunk, speakers: [Speaker], reason: String?) async throws -> NotesPart {
        let basic = try await HeuristicEnhancer().enhance(segments: chunk.segments, speakers: speakers, userNotes: "")
        let points = basic.summary
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("- ") }
            .map { String($0.dropFirst(2)) }
        return NotesPart(
            topic: "",
            keyPoints: points,
            decisions: basic.decisions,
            actions: Array(basic.actions.prefix(Self.actionsPerPart)),
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

    /// One request to the model for structured notes.
    private func generate<Content: Generable>(_ prompt: String, as type: Content.Type) async throws -> Content {
        try await Self.withRetries {
            let session = LanguageModelSession(instructions: Self.instructions)
            return try await session.respond(to: prompt, generating: type).content
        }
    }

    /// Runs a request, retrying with growing waits while the system is busy, and once after a
    /// generic system error, which is often temporary. Safety blocks aren't retried.
    static func withRetries<Value>(_ request: () async throws -> Value) async throws -> Value {
        var attempt = 0
        var retriedSystemError = false
        while true {
            do {
                return try await request()
            } catch let error as LanguageModelSession.GenerationError {
                guard case .rateLimited = error else { throw error }
                guard attempt < Self.busyRetryDelays.count else { throw NotesEnhancerError.busy }
                try await Task.sleep(for: Self.busyRetryDelays[attempt])
                attempt += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard !retriedSystemError, !Self.isSafetyBlock(error) else { throw error }
                retriedSystemError = true
                try await Task.sleep(for: .seconds(2))
            }
        }
    }
}
#endif
