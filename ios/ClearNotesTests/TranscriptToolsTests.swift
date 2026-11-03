import SwiftData
import XCTest
@testable import ClearNotes

final class TranscriptBuilderTests: XCTestCase {
    func testLinesEndAtSentencesAndPauses() {
        let words = [
            TimedWord(text: "Hello", start: 0, end: 0.4),
            TimedWord(text: "there.", start: 0.5, end: 0.9),
            TimedWord(text: "How", start: 1.0, end: 1.2),
            TimedWord(text: "are", start: 1.25, end: 1.4),
            TimedWord(text: "you", start: 1.45, end: 1.8),
            TimedWord(text: "Fine", start: 4.0, end: 4.3),
        ]

        let lines = TranscriptBuilder.segments(from: words)

        XCTAssertEqual(lines.map(\.text), ["Hello there.", "How are you", "Fine"])
        XCTAssertEqual(lines[1].start, 1.0)
        XCTAssertEqual(lines[1].end, 1.8)
        XCTAssertEqual(lines[1].words?.count, 3, "Word timings are kept for speaker separation")
    }

    func testKnownSpeakersAreKeptAndSplitLines() {
        let words = [
            TimedWord(text: "I'll", start: 0, end: 0.3),
            TimedWord(text: "send", start: 0.35, end: 0.6),
            TimedWord(text: "it", start: 0.65, end: 0.8),
            TimedWord(text: "Thanks", start: 0.9, end: 1.1),
        ]
        let old = [
            TranscriptSegment(start: 0, end: 0.85, text: "I'll send it", speakerID: "S1"),
            TranscriptSegment(start: 0.85, end: 1.2, text: "Thanks", speakerID: "S2"),
        ]

        let lines = TranscriptBuilder.segments(from: words) { TranscriptBuilder.speaker(at: $0, in: old) }

        XCTAssertEqual(lines.map(\.text), ["I'll send it", "Thanks"])
        XCTAssertEqual(lines.map(\.speakerID), ["S1", "S2"])
        XCTAssertEqual(TranscriptBuilder.speaker(at: 5, in: old), "S2", "Nearest line when none covers the moment")
    }

    func testASecondPassThatLostMostWordsIsNotUsed() {
        let original = [TranscriptSegment(start: 0, end: 5, text: "one two three four five six seven eight nine ten")]
        XCTAssertFalse(TranscriptBuilder.isUsable([], comparedWith: original))
        XCTAssertFalse(TranscriptBuilder.isUsable([TranscriptSegment(start: 0, end: 5, text: "one two three")], comparedWith: original))
        XCTAssertTrue(TranscriptBuilder.isUsable([TranscriptSegment(start: 0, end: 5, text: "one two three four five six seven")], comparedWith: original))
    }
}

final class VocabularyFixerTests: XCTestCase {
    private let dictionary: Set<String> = [
        "we", "moved", "it", "to", "in", "tune", "last", "week", "is", "working", "call", "support",
        "get", "the", "petal", "ready", "said", "yes", "send", "via", "please",
    ]
    private func isRealWord(_ word: String) -> Bool { dictionary.contains(word.lowercased()) }

    func testExactMatchesIgnoringCaseAndSpacesAreSpelledFromTheList() {
        XCTAssertEqual(
            VocabularyFixer.fix("We moved it to in tune last week.", terms: ["Intune"], isRealWord: isRealWord),
            "We moved it to Intune last week."
        )
        XCTAssertEqual(
            VocabularyFixer.fix("Send it via nhsmail, please.", terms: ["NHSmail"], isRealWord: isRealWord),
            "Send it via NHSmail, please."
        )
    }

    func testShortRealWordsAreNeverChanged() {
        XCTAssertEqual(VocabularyFixer.fix("Is it working?", terms: ["IT"], isRealWord: isRealWord), "Is it working?")
        XCTAssertEqual(VocabularyFixer.fix("Call IT support", terms: ["IT"], isRealWord: isRealWord), "Call IT support")
    }

    func testNearMissesAreFixedOnlyWhenNotARealWord() {
        XCTAssertEqual(VocabularyFixer.fix("Jayson said yes.", terms: ["Jason"], isRealWord: isRealWord), "Jason said yes.")
        XCTAssertEqual(VocabularyFixer.fix("Get the petal ready", terms: ["Patel"], isRealWord: isRealWord), "Get the petal ready")
    }

    func testEditDistanceAndTermsFromText() {
        XCTAssertEqual(VocabularyFixer.editDistance("kitten", "sitting"), 3)
        XCTAssertEqual(Vocabulary.terms(from: "Intune, NHSmail\nPriya Sharma\n\n"), ["Intune", "NHSmail", "Priya Sharma"])
    }
}

@MainActor
final class LineEditingTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    func testEditingALineChangesItsTextAndAsksForFreshNotes() throws {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let line = TranscriptSegment(
            start: 0, end: 2, text: "I'm just a petrock",
            words: [TimedWord(text: "I'm", start: 0, end: 0.5)]
        )
        let meeting = Meeting(title: "Test", segments: [line])
        container.mainContext.insert(meeting)
        meeting.processingState = .ready
        let revision = meeting.revision

        meeting.editSegmentText(line.id, to: "  I'm just a petrolhead ")

        XCTAssertEqual(meeting.segments.first?.text, "I'm just a petrolhead")
        XCTAssertNil(meeting.segments.first?.words, "Old word timings no longer match")
        XCTAssertGreaterThan(meeting.revision, revision)
        XCTAssertTrue(meeting.notesNeedRefresh)
    }
}
