import SwiftData
import XCTest
@testable import ClearNotes

final class MeetingFileFormatTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("MeetingFileTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func sample(recordingBytes: Int64? = nil) -> SharedMeeting {
        SharedMeeting(
            formatVersion: SharedMeeting.currentFormatVersion,
            meetingID: UUID(),
            title: "Weekly check-in",
            date: Date(timeIntervalSince1970: 1_793_000_000),
            duration: 1_800,
            sharedBy: "Priya Sharma",
            sharedAt: Date(timeIntervalSince1970: 1_793_005_000),
            invited: ["Priya Sharma", "Tom Ellis"],
            speakers: [SharedMeeting.Person(id: "S1", number: 1, name: "Priya Sharma")],
            transcript: [SharedMeeting.Line(id: UUID(), start: 0, end: 4, text: "The new rota is ready.", speakerID: "S1")],
            summary: "- The new rota is ready.",
            topics: [SharedMeeting.Section(title: "Rota", start: 0, end: 4, points: ["The rota is ready"])],
            decisions: ["The rota starts on 1 December"],
            actions: [SharedMeeting.Action(text: "Share the rota", owner: "Priya Sharma", due: "by Friday", status: "open", sourceLineID: nil)],
            minutes: "Weekly check-in\n1. Rota",
            privateNotes: nil,
            notesCaveat: nil,
            notesSource: "Test",
            recording: recordingBytes.map { SharedMeeting.Recording(byteCount: $0, fileExtension: "caf") }
        )
    }

    private func audio(bytes: Int) throws -> URL {
        let url = folder.appendingPathComponent("audio-in.caf")
        var data = Data(count: bytes)
        for index in stride(from: 0, to: bytes, by: 997) { data[index] = UInt8(index % 251) }
        try data.write(to: url)
        return url
    }

    func testAPlainFileRoundTrips() throws {
        let meeting = sample()
        let url = folder.appendingPathComponent("plain.clearnotes")
        try MeetingFileFormat.write(meeting, audio: nil, password: nil, to: url)

        XCTAssertFalse(try MeetingFileFormat.isProtected(url))
        XCTAssertEqual(try MeetingFileFormat.read(url, password: nil), meeting)
    }

    func testAPasswordProtectedFileWithARecordingRoundTrips() throws {
        // Two and a half pieces of audio, so the chunking is exercised.
        let input = try audio(bytes: MeetingFileFormat.audioChunkSize * 5 / 2)
        let meeting = sample(recordingBytes: Int64(MeetingFileFormat.audioChunkSize * 5 / 2))
        let url = folder.appendingPathComponent("protected.clearnotes")
        try MeetingFileFormat.write(meeting, audio: input, password: "correct horse", to: url, iterations: 1_000)

        XCTAssertTrue(try MeetingFileFormat.isProtected(url))
        XCTAssertThrowsError(try MeetingFileFormat.read(url, password: nil)) {
            XCTAssertEqual($0 as? MeetingFileError, .passwordRequired)
        }
        XCTAssertThrowsError(try MeetingFileFormat.read(url, password: "wrong horse")) {
            XCTAssertEqual($0 as? MeetingFileError, .wrongPassword)
        }

        let output = folder.appendingPathComponent("audio-out.caf")
        let read = try MeetingFileFormat.read(url, password: "correct horse", writingAudioTo: output)
        XCTAssertEqual(read, meeting)
        XCTAssertEqual(try Data(contentsOf: output), try Data(contentsOf: input))

        // The transcript isn't readable in the file itself.
        let raw = try Data(contentsOf: url)
        XCTAssertNil(raw.range(of: Data("The new rota is ready.".utf8)))
    }

    func testTamperingAndTruncationAreCaught() throws {
        let input = try audio(bytes: 300_000)
        for password in [nil, "correct horse"] as [String?] {
            let url = folder.appendingPathComponent("file.clearnotes")
            try? FileManager.default.removeItem(at: url)
            try MeetingFileFormat.write(sample(recordingBytes: 300_000), audio: input, password: password, to: url, iterations: 1_000)
            let original = try Data(contentsOf: url)
            let output = folder.appendingPathComponent("out.caf")

            // A changed byte in the recording.
            var tampered = original
            tampered[tampered.count - 1_000] ^= 0xFF
            try tampered.write(to: url)
            XCTAssertThrowsError(try MeetingFileFormat.read(url, password: password, writingAudioTo: output)) {
                XCTAssertEqual($0 as? MeetingFileError, .damaged)
            }

            // A file cut short.
            try original.prefix(original.count - 50).write(to: url)
            XCTAssertThrowsError(try MeetingFileFormat.read(url, password: password, writingAudioTo: output)) {
                XCTAssertEqual($0 as? MeetingFileError, .damaged)
            }
        }
    }

    func testOtherFilesAreRefused() throws {
        let url = folder.appendingPathComponent("notes.clearnotes")
        try Data("Just some text, not a meeting".utf8).write(to: url)
        XCTAssertThrowsError(try MeetingFileFormat.read(url, password: nil)) {
            XCTAssertEqual($0 as? MeetingFileError, .notAMeetingFile)
        }
    }

    func testFileNamesAreSafe() {
        let name = MeetingSharing.fileName(title: "Budget: Q3/Q4?", date: Date(timeIntervalSince1970: 1_793_000_000))
        XCTAssertTrue(name.hasPrefix("Budget  Q3 Q4"))
        XCTAssertTrue(name.hasSuffix(".clearnotes"))
        XCTAssertFalse(name.contains("/"))
    }
}

@MainActor
final class MeetingSharingTests: XCTestCase {
    /// Held for the whole test. SwiftData models stop saving changes once their container is released.
    private var container: ModelContainer?

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        self.container = container
        return container
    }

    private func sharedMeeting(in container: ModelContainer) -> Meeting {
        let line = TranscriptSegment(start: 0, end: 4, text: "I'll share the rota on Friday.", speakerID: "S1")
        let meeting = Meeting(title: "Weekly check-in", duration: 600, userNotes: "Remember to ask about leave", segments: [line])
        container.mainContext.insert(meeting)
        meeting.speakers = [Speaker(id: "S1", number: 1, name: "Priya Sharma", embedding: [0.1, 0.2, 0.3])]
        meeting.summary = "- The rota is ready."
        meeting.decisions = ["The rota starts on 1 December"]
        let open = ActionItem(text: "Share the rota", owner: "Priya Sharma", status: .open, sourceSegmentID: line.id)
        let dismissed = ActionItem(text: "Book a room", status: .dismissed)
        for action in [open, dismissed] {
            container.mainContext.insert(action)
            meeting.actions.append(action)
        }
        return meeting
    }

    func testVoicesAndPrivateNotesStayBehindUnlessChosen() throws {
        let container = try makeContainer()
        let meeting = sharedMeeting(in: container)

        let shared = MeetingSharing.document(for: meeting, options: ShareOptions(), sharedBy: "Priya Sharma", recordingBytes: nil)

        XCTAssertEqual(shared.speakers, [SharedMeeting.Person(id: "S1", number: 1, name: "Priya Sharma")])
        XCTAssertNil(shared.privateNotes)
        XCTAssertEqual(shared.actions.map(\.text), ["Share the rota"], "Dismissed suggestions aren't shared")
        XCTAssertEqual(shared.meetingID, meeting.shareID)

        let withNotes = MeetingSharing.document(
            for: meeting, options: ShareOptions(includePrivateNotes: true), sharedBy: nil, recordingBytes: nil
        )
        XCTAssertEqual(withNotes.privateNotes, "Remember to ask about leave")
        XCTAssertEqual(withNotes.meetingID, shared.meetingID, "Every copy of a meeting has the same ID")
    }

    func testImportingCreatesACopyAndImportingAgainUpdatesIt() throws {
        let senderContainer = try makeContainer()
        let original = sharedMeeting(in: senderContainer)
        var shared = MeetingSharing.document(for: original, options: ShareOptions(), sharedBy: "Priya Sharma", recordingBytes: nil)

        let recipient = try ModelContainer(
            for: Meeting.self, ActionItem.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = recipient.mainContext
        XCTAssertNil(MeetingSharing.existingCopy(of: shared, in: context))

        let copy = MeetingSharing.importMeeting(shared, recording: nil, replacing: nil, into: context)
        XCTAssertEqual(copy.title, "Weekly check-in")
        XCTAssertEqual(copy.sharedBy, "Priya Sharma")
        XCTAssertEqual(copy.processingState, .ready)
        XCTAssertEqual(copy.speakers.first?.name, "Priya Sharma")
        XCTAssertNil(copy.speakers.first?.embedding)
        XCTAssertEqual(copy.actions.map(\.text), ["Share the rota"])
        XCTAssertEqual(copy.actions.first?.sourceSegmentID, original.segments.first?.id, "Actions still link to their line")
        copy.userNotes = "My own notes"

        // The sender updates the meeting and shares it again.
        shared.actions.append(SharedMeeting.Action(text: "Send the budget", owner: nil, due: nil, status: "open", sourceLineID: nil))
        let existing = MeetingSharing.existingCopy(of: shared, in: context)
        XCTAssertTrue(existing === copy)
        MeetingSharing.importMeeting(shared, recording: nil, replacing: existing, into: context)

        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(meetings.count, 1)
        XCTAssertEqual(Set(copy.actions.map(\.text)), ["Share the rota", "Send the budget"])
        XCTAssertEqual(copy.userNotes, "My own notes", "The recipient's own notes are kept")
        _ = recipient
    }
}

final class SummaryBulletTests: XCTestCase {
    func testPointsWrittenOnOneLineAreSplit() {
        XCTAssertEqual(
            NotesText.bullets(from: "- Tom is away next week. - The template needs to be the same. - Phase three is hardest."),
            ["Tom is away next week.", "The template needs to be the same.", "Phase three is hardest."]
        )
        XCTAssertEqual(NotesText.splitRunTogether("The Wi-Fi works from 10 - 12 each day."), ["The Wi-Fi works from 10 - 12 each day."])
    }

    func testALockedFileErrorIsRecognised() {
        XCTAssertTrue(AppActivity.isLockedFileError(NSError(domain: "com.apple.coreaudio.avfaudio", code: -54)))
        let wrapped = NSError(domain: "Wrapper", code: 1, userInfo: [NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))])
        XCTAssertTrue(AppActivity.isLockedFileError(wrapped))
        XCTAssertFalse(AppActivity.isLockedFileError(NSError(domain: "Other", code: 2)))
    }
}
