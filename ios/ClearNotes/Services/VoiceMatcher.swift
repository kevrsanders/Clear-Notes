import Foundation
import SwiftData

/// A remembered voice, as the matcher sees it.
struct VoiceCandidate: Sendable {
    var id: String
    var name: String
    var samples: [[Float]]
    var confirmations: Int
}

struct VoiceMatch: Equatable, Sendable {
    var speakerID: String
    var candidateID: String
    var name: String
    var score: Float
    /// Strong enough, and confirmed often enough, to fill in the name without asking.
    var isConfident: Bool
}

/// Compares voices in a new meeting with remembered ones.
enum VoiceMatcher {
    /// Cosine similarity needed to suggest a name.
    static let suggestThreshold: Float = 0.65
    /// Cosine similarity needed to fill in a name automatically…
    static let confidentThreshold: Float = 0.78
    /// …once the user has confirmed the voice this many times.
    static let confirmationsForAuto = 3

    static func normalized(_ vector: [Float]) -> [Float] {
        let length = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard length > 0 else { return [] }
        return vector.map { $0 / length }
    }

    static func similarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let na = normalized(a)
        let nb = normalized(b)
        guard !na.isEmpty, !nb.isEmpty else { return 0 }
        return zip(na, nb).reduce(0) { $0 + $1.0 * $1.1 }
    }

    /// Best similarity between a voice and any of a candidate's samples.
    static func score(_ embedding: [Float], against candidate: VoiceCandidate) -> Float {
        candidate.samples.map { similarity(embedding, $0) }.max() ?? 0
    }

    /// Pairs speakers with remembered voices, best matches first, each used at most once.
    static func match(
        speakers: [(id: String, embedding: [Float])],
        candidates: [VoiceCandidate]
    ) -> [VoiceMatch] {
        var pairs: [VoiceMatch] = []
        for speaker in speakers where !speaker.embedding.isEmpty {
            for candidate in candidates {
                let value = Self.score(speaker.embedding, against: candidate)
                guard value >= suggestThreshold else { continue }
                pairs.append(VoiceMatch(
                    speakerID: speaker.id,
                    candidateID: candidate.id,
                    name: candidate.name,
                    score: value,
                    isConfident: value >= confidentThreshold && candidate.confirmations >= confirmationsForAuto
                ))
            }
        }
        var usedSpeakers = Set<String>()
        var usedCandidates = Set<String>()
        var result: [VoiceMatch] = []
        for pair in pairs.sorted(by: { $0.score > $1.score }) {
            guard !usedSpeakers.contains(pair.speakerID), !usedCandidates.contains(pair.candidateID) else { continue }
            usedSpeakers.insert(pair.speakerID)
            usedCandidates.insert(pair.candidateID)
            result.append(pair)
        }
        return result
    }
}

/// Saves, finds and deletes remembered voices.
@MainActor
enum VoiceLibrary {
    static let maximumSamples = 10

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: SettingsKeys.rememberVoices)
    }

    /// Remembers (or strengthens) a voice under a name. The caller has confirmed consent.
    @discardableResult
    static func remember(name: String, embedding: [Float], in context: ModelContext) -> VoiceProfile? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !embedding.isEmpty else { return nil }
        let profiles = (try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? []
        if let existing = profiles.first(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            existing.samples = Array((existing.samples + [embedding]).suffix(maximumSamples))
            existing.confirmations += 1
            existing.lastHeardAt = .now
            try? context.save()
            return existing
        }
        let profile = VoiceProfile(name: trimmed, sample: embedding)
        context.insert(profile)
        try? context.save()
        return profile
    }

    /// Suggests or fills in names for a meeting's speakers from remembered voices.
    static func applyMatches(to meeting: Meeting) {
        guard isEnabled, let context = meeting.modelContext else { return }
        let profiles = (try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? []
        guard !profiles.isEmpty else { return }
        let candidates = profiles.map {
            VoiceCandidate(id: $0.profileID.uuidString, name: $0.name, samples: $0.samples, confirmations: $0.confirmations)
        }
        let speakers = meeting.speakers.compactMap { speaker in
            speaker.embedding.map { (id: speaker.id, embedding: $0) }
        }
        let matches = VoiceMatcher.match(speakers: speakers, candidates: candidates)
        guard !matches.isEmpty else { return }

        meeting.speakers = meeting.speakers.map { speaker in
            guard speaker.name == nil, let match = matches.first(where: { $0.speakerID == speaker.id }) else { return speaker }
            var speaker = speaker
            if match.isConfident {
                speaker.name = match.name
                speaker.matchedProfileID = match.candidateID
            } else {
                speaker.suggestedName = match.name
                speaker.suggestedProfileID = match.candidateID
            }
            return speaker
        }
    }

    /// Deletes every remembered voice, and the voiceprints kept on meetings.
    static func deleteAll(in context: ModelContext) {
        for profile in (try? context.fetch(FetchDescriptor<VoiceProfile>())) ?? [] {
            context.delete(profile)
        }
        for meeting in (try? context.fetch(FetchDescriptor<Meeting>())) ?? [] {
            meeting.forgetVoiceprints()
        }
        try? context.save()
    }
}
