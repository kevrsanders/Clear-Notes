import Foundation

/// Combines the transcript with speaker separation output.
///
/// Each word is given to the voice speaking at that moment, and consecutive words from
/// the same voice become one segment, so a chunk where two people spoke is split in two.
enum SpeakerAssigner {
    /// Word runs shorter than this are treated as separation noise and kept with the previous voice.
    static let minimumRunLength = 3

    static func assign(
        _ segments: [TranscriptSegment],
        turns: [SpeakerTurn]
    ) -> (segments: [TranscriptSegment], speakers: [Speaker]) {
        let sortedTurns = turns.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !sortedTurns.isEmpty else { return (segments, []) }

        // Stable IDs in order of first appearance: S1, S2, ...
        var idForLabel: [String: String] = [:]
        for turn in sortedTurns where idForLabel[turn.speaker] == nil {
            idForLabel[turn.speaker] = "S\(idForLabel.count + 1)"
        }

        var result: [TranscriptSegment] = []
        for segment in segments {
            if let words = segment.words, hasUsableTimings(words) {
                result += split(segment, words: words, turns: sortedTurns, ids: idForLabel)
            } else {
                var copy = segment
                copy.speakerID = dominantSpeaker(from: segment.start, to: segment.end, turns: sortedTurns)
                    .flatMap { idForLabel[$0] }
                copy.words = nil
                result.append(copy)
            }
        }

        let used = Set(result.compactMap(\.speakerID))
        let voiceprints = centroids(sortedTurns)
        let speakers = idForLabel
            .filter { used.contains($0.value) }
            .compactMap { label, id in
                Int(id.dropFirst()).map { number in
                    let voiceprint = voiceprints[label] ?? []
                    return Speaker(id: id, number: number, embedding: voiceprint.isEmpty ? nil : voiceprint)
                }
            }
            .sorted { $0.number < $1.number }
        return (result, speakers)
    }

    /// One voiceprint per separator label: the duration-weighted average of its turns, normalised.
    static func centroids(_ turns: [SpeakerTurn]) -> [String: [Float]] {
        var sums: [String: [Float]] = [:]
        for turn in turns where !turn.embedding.isEmpty {
            let weight = Float(max(turn.end - turn.start, 0.1))
            if let sum = sums[turn.speaker] {
                guard sum.count == turn.embedding.count else { continue }
                sums[turn.speaker] = zip(sum, turn.embedding).map { $0 + $1 * weight }
            } else {
                sums[turn.speaker] = turn.embedding.map { $0 * weight }
            }
        }
        return sums.mapValues(VoiceMatcher.normalized)
    }

    // MARK: - Helpers

    /// Partial results can arrive without real timings (every word at zero).
    private static func hasUsableTimings(_ words: [TimedWord]) -> Bool {
        guard let first = words.first, let last = words.last else { return false }
        return last.end > first.start
    }

    private static func split(
        _ segment: TranscriptSegment,
        words: [TimedWord],
        turns: [SpeakerTurn],
        ids: [String: String]
    ) -> [TranscriptSegment] {
        var runs: [(speaker: String?, words: [TimedWord])] = []
        for word in words {
            let voice = Self.speaker(at: (word.start + word.end) / 2, turns: turns).flatMap { ids[$0] }
            if let last = runs.last, last.speaker == voice {
                runs[runs.count - 1].words.append(word)
            } else {
                runs.append((voice, [word]))
            }
        }

        // Smooth out very short runs, which are usually separation errors.
        var smoothed: [(speaker: String?, words: [TimedWord])] = []
        for run in runs {
            if let last = smoothed.last, run.words.count < minimumRunLength || last.speaker == run.speaker {
                smoothed[smoothed.count - 1].words += run.words
            } else {
                smoothed.append(run)
            }
        }
        if smoothed.count > 1, smoothed[0].words.count < minimumRunLength {
            smoothed[1].words.insert(contentsOf: smoothed[0].words, at: 0)
            smoothed.removeFirst()
        }

        return smoothed.enumerated().map { index, run in
            TranscriptSegment(
                id: index == 0 ? segment.id : UUID(),
                start: run.words.first?.start ?? segment.start,
                end: run.words.last?.end ?? segment.end,
                text: run.words.map(\.text).joined(separator: " "),
                speakerID: run.speaker,
                words: nil
            )
        }
    }

    /// The voice speaking at a moment, or the nearest one if nobody was.
    static func speaker(at time: TimeInterval, turns: [SpeakerTurn]) -> String? {
        if let turn = turns.first(where: { $0.start <= time && time <= $0.end }) {
            return turn.speaker
        }
        return turns.min { distance(from: time, to: $0) < distance(from: time, to: $1) }?.speaker
    }

    private static func distance(from time: TimeInterval, to turn: SpeakerTurn) -> TimeInterval {
        time < turn.start ? turn.start - time : time - turn.end
    }

    /// The voice that spoke most between two times.
    static func dominantSpeaker(from start: TimeInterval, to end: TimeInterval, turns: [SpeakerTurn]) -> String? {
        var totals: [String: TimeInterval] = [:]
        for turn in turns {
            let overlap = min(end, turn.end) - max(start, turn.start)
            if overlap > 0 { totals[turn.speaker, default: 0] += overlap }
        }
        if let best = totals.max(by: { $0.value < $1.value }) {
            return best.key
        }
        return speaker(at: (start + end) / 2, turns: turns)
    }
}
