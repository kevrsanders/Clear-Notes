import SwiftData
import XCTest
@testable import ClearNotes

final class VoiceMatcherTests: XCTestCase {
    private let priya: [Float] = [1, 0, 0]
    private let tom: [Float] = [0, 1, 0]

    func testSimilarity() {
        XCTAssertEqual(VoiceMatcher.similarity(priya, [2, 0, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(VoiceMatcher.similarity(priya, tom), 0, accuracy: 0.0001)
        XCTAssertEqual(VoiceMatcher.similarity(priya, [1, 0]), 0, "Different lengths never match")
    }

    func testMatchesEachVoiceOnceBestFirst() {
        let candidates = [
            VoiceCandidate(id: "p", name: "Priya", samples: [priya], confirmations: 1),
            VoiceCandidate(id: "t", name: "Tom", samples: [tom], confirmations: 5),
        ]
        let matches = VoiceMatcher.match(
            speakers: [(id: "S1", embedding: [0.1, 1, 0]), (id: "S2", embedding: [1, 0.05, 0]), (id: "S3", embedding: [0, 0, 1])],
            candidates: candidates
        )
        XCTAssertEqual(Set(matches.map { "\($0.speakerID)=\($0.name)" }), ["S1=Tom", "S2=Priya"])
        // Tom is confirmed often and the match is strong, so he can be named automatically.
        XCTAssertEqual(matches.first { $0.name == "Tom" }?.isConfident, true)
        // Priya has only been confirmed once, so she is suggested, not filled in.
        XCTAssertEqual(matches.first { $0.name == "Priya" }?.isConfident, false)
    }

    func testWeakMatchesAreIgnored() {
        let candidates = [VoiceCandidate(id: "p", name: "Priya", samples: [priya], confirmations: 5)]
        XCTAssertTrue(VoiceMatcher.match(speakers: [(id: "S1", embedding: [1, 1.5, 0])], candidates: candidates).isEmpty)
    }

    func testSpeakersGetANormalisedVoiceprint() throws {
        let turns = [
            SpeakerTurn(speaker: "a", start: 0, end: 3, embedding: [2, 0]),
            SpeakerTurn(speaker: "a", start: 3, end: 4, embedding: [0, 2]),
            SpeakerTurn(speaker: "b", start: 4, end: 6),
        ]
        let segment = TranscriptSegment(start: 0, end: 6, text: "Hello there")
        let result = SpeakerAssigner.assign([segment], turns: turns)
        let voiceprint = try XCTUnwrap(SpeakerAssigner.centroids(turns)["a"])
        XCTAssertEqual(voiceprint.reduce(0) { $0 + $1 * $1 }, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(voiceprint[0], voiceprint[1], "Longer turns count for more")
        XCTAssertNil(SpeakerAssigner.centroids(turns)["b"], "No embedding, no voiceprint")
        XCTAssertNotNil(result.speakers.first?.embedding)
    }
}

@MainActor
final class VoiceLibraryTests: XCTestCase {
    func testRememberingTheSameNameAddsSamplesUpToTheLimit() throws {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self, VoiceProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        for index in 0..<(VoiceLibrary.maximumSamples + 3) {
            VoiceLibrary.remember(name: index == 0 ? "Priya" : "priya ", embedding: [Float(index), 1], in: context)
        }
        let profiles = try context.fetch(FetchDescriptor<VoiceProfile>())
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.name, "Priya")
        XCTAssertEqual(profiles.first?.samples.count, VoiceLibrary.maximumSamples)
        XCTAssertEqual(profiles.first?.samples.last, [Float(VoiceLibrary.maximumSamples + 2), 1])
        XCTAssertEqual(profiles.first?.confirmations, VoiceLibrary.maximumSamples + 3)
    }
}
