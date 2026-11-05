import SwiftData
import XCTest
@testable import ClearNotes

/// An in-memory place to save parts, standing in for the meeting.
private actor MemoryProgress: NotesProgress {
    var saved: [String: [NotesPart]] = [:]
    var updates: [String] = []

    func savedParts(for key: String) async -> [NotesPart]? { saved[key] }
    func save(_ parts: [NotesPart], for key: String) async { saved[key] = parts }
    func update(done: Int, of total: Int) async { updates.append("\(done)/\(total)") }
}

private struct Interrupted: Error {}

final class PartByPartTests: XCTestCase {
    private func part(_ topic: String) -> NotesPart {
        NotesPart(topic: topic, keyPoints: [], decisions: [], actions: [], start: 0, end: 0)
    }

    func testAPausedRunCarriesOnFromTheNextPart() async throws {
        let pieces = ["first piece", "second piece", "third piece", "fourth piece"]
        let progress = MemoryProgress()

        // The first run is interrupted while writing the third piece (e.g. iOS paused the app).
        var firstRunWrote: [Int] = []
        do {
            _ = try await PartByPart.run(pieces, notes: "", progress: progress) { index in
                if index == 2 { throw Interrupted() }
                firstRunWrote.append(index)
                return [self.part("Topic \(index)")]
            }
            XCTFail("Expected the first run to stop")
        } catch is Interrupted {}
        XCTAssertEqual(firstRunWrote, [0, 1])

        // The next run reuses the first two and writes only the rest.
        var secondRunWrote: [Int] = []
        let parts = try await PartByPart.run(pieces, notes: "", progress: progress) { index in
            secondRunWrote.append(index)
            return [self.part("Topic \(index)")]
        }

        XCTAssertEqual(secondRunWrote, [2, 3])
        XCTAssertEqual(parts.map(\.topic), ["Topic 0", "Topic 1", "Topic 2", "Topic 3"])
        let updates = await progress.updates
        XCTAssertEqual(Array(updates.suffix(5)), ["0/4", "1/4", "2/4", "3/4", "4/4"])
    }

    func testChangedTextIsWrittenAgain() async throws {
        let progress = MemoryProgress()
        _ = try await PartByPart.run(["Priya said the rota is ready."], notes: "", progress: progress) { _ in [self.part("Old")] }

        // A speaker was named, so the piece's text changed: the saved part no longer applies.
        var wrote = 0
        let parts = try await PartByPart.run(["Priya Sharma said the rota is ready."], notes: "", progress: progress) { _ in
            wrote += 1
            return [self.part("New")]
        }
        XCTAssertEqual(wrote, 1)
        XCTAssertEqual(parts.map(\.topic), ["New"])
    }

    func testKeysAreStableAndSpecific() {
        let key = NotesPartKey.make(transcript: "[0:05] Priya: Hello", notes: "")
        XCTAssertEqual(key, NotesPartKey.make(transcript: "[0:05] Priya: Hello", notes: ""))
        XCTAssertEqual(key.count, 32)
        XCTAssertNotEqual(key, NotesPartKey.make(transcript: "[0:05] Priya: Hello.", notes: ""))
        XCTAssertNotEqual(key, NotesPartKey.make(transcript: "[0:05] Priya: Hello", notes: "Budget"))
    }

    func testProgressWording() {
        XCTAssertEqual(ProcessingProgress.notesDetail(partsDone: 11, partsTotal: 38), "Part 12 of 38")
        XCTAssertEqual(ProcessingProgress.notesDetail(partsDone: 38, partsTotal: 38), "Writing the summary")
        XCTAssertNil(ProcessingProgress.notesDetail(partsDone: 0, partsTotal: 1), "A short meeting is one part")
        XCTAssertEqual(ProcessingProgress.subtitle(stage: .notes, partsDone: 11, partsTotal: 38), "Writing notes · part 12 of 38")
        XCTAssertEqual(ProcessingProgress.subtitle(stage: .speakers, partsDone: 0, partsTotal: 0), "Identifying speakers")

        let early = ProcessingProgress.fraction(stage: .notes, partsDone: 0, partsTotal: 38)
        let later = ProcessingProgress.fraction(stage: .notes, partsDone: 19, partsTotal: 38)
        XCTAssertLessThan(ProcessingProgress.fraction(stage: .speakers, partsDone: 0, partsTotal: 0), early)
        XCTAssertLessThan(early, later)
        XCTAssertLessThan(ProcessingProgress.fraction(stage: .notes, partsDone: 38, partsTotal: 38), 1)
    }
}

@MainActor
final class SavedNotesProgressTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    private func makeMeeting() throws -> Meeting {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        let meeting = Meeting(title: "Test", segments: [
            TranscriptSegment(start: 0, end: 4, text: "We looked at the patching backlog for the servers this week."),
            TranscriptSegment(start: 4, end: 8, text: "I'll send the revised firewall change to the CAB by Friday."),
        ])
        container.mainContext.insert(meeting)
        return meeting
    }

    func testSavedPartsSurviveOnTheMeeting() async throws {
        let meeting = try makeMeeting()
        let saved = NotesPart(
            topic: "Patching",
            keyPoints: ["The backlog was reviewed"],
            decisions: [],
            actions: [ExtractedAction(task: "Send the firewall change", owner: "Tom", due: "by Friday")],
            start: 0,
            end: 8
        )
        let first = MeetingNotesProgress(meeting: meeting)
        await first.save([saved], for: "abc")
        await first.update(done: 1, of: 3)

        // As after a restart: a new progress object reads what the first one saved.
        let second = MeetingNotesProgress(meeting: meeting)
        let reloaded = await second.savedParts(for: "abc")
        XCTAssertEqual(reloaded, [saved])
        XCTAssertTrue(second.hasSavedParts)
        XCTAssertEqual(meeting.notesPartsDone, 1)
        XCTAssertEqual(meeting.notesPartsTotal, 3)
    }

    func testFinishedNotesClearTheSavedParts() async throws {
        let meeting = try makeMeeting()
        meeting.notesProgressData = NotesCheckpoint.encode([
            "abc": [NotesPart(topic: "Old", keyPoints: [], decisions: [], actions: [], start: 0, end: 8)],
        ])

        await MeetingProcessor.process(meeting, enhancer: HeuristicEnhancer(), separator: nil)

        XCTAssertEqual(meeting.processingState, .ready)
        XCTAssertNil(meeting.notesProgressData)
        XCTAssertEqual(meeting.notesPartsTotal, 0)
    }
}
