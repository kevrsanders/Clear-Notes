import Foundation
import SwiftData

/// What goes into a shared meeting file besides the meeting itself.
struct ShareOptions: Sendable {
    var includePrivateNotes = false
    var includeRecording = false
    /// Encrypts the file when set.
    var password: String?
}

/// Shares meetings as `.clearnotes` files and imports them.
enum MeetingSharing {
    /// Where files are made for the share sheet. Emptied after sharing and at launch.
    static var shareFolder: URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func clearSharedFiles() {
        try? FileManager.default.removeItem(at: FileManager.default.temporaryDirectory.appendingPathComponent("Share", isDirectory: true))
    }

    static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    /// "Weekly check-in – 5 Nov 2026.clearnotes"
    static func fileName(title: String, date: Date) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.newlines).union(.controlCharacters)
        let cleanTitle = title.components(separatedBy: unsafe).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let day = date.formatted(.dateTime.day().month(.abbreviated).year())
        return "\(cleanTitle.isEmpty ? "Meeting" : String(cleanTitle.prefix(80))) – \(day).clearnotes"
    }

    // MARK: Sharing

    /// The meeting as it's shared. Remembered voiceprints and word timings are never included.
    @MainActor
    static func document(for meeting: Meeting, options: ShareOptions, sharedBy: String?, recordingBytes: Int64?) -> SharedMeeting {
        if meeting.shareID == nil {
            meeting.shareID = UUID()
        }
        let notes = meeting.userNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        return SharedMeeting(
            formatVersion: SharedMeeting.currentFormatVersion,
            meetingID: meeting.shareID ?? UUID(),
            title: meeting.title,
            date: meeting.createdAt,
            duration: meeting.duration,
            sharedBy: sharedBy.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 },
            sharedAt: .now,
            invited: meeting.attendees,
            speakers: meeting.speakers.sorted { $0.number < $1.number }.map {
                SharedMeeting.Person(id: $0.id, number: $0.number, name: $0.name)
            },
            transcript: meeting.segments.map {
                SharedMeeting.Line(id: $0.id, start: $0.start, end: $0.end, text: $0.text, speakerID: $0.speakerID)
            },
            summary: meeting.summary,
            topics: meeting.topics.map {
                SharedMeeting.Section(title: $0.title, start: $0.start, end: $0.end, points: $0.points)
            },
            decisions: meeting.decisions,
            actions: meeting.actions
                .filter { $0.status != .dismissed }
                .sorted { $0.createdAt < $1.createdAt }
                .map {
                    SharedMeeting.Action(
                        text: $0.text, owner: $0.owner, due: $0.due,
                        status: $0.status.rawValue, sourceLineID: $0.sourceSegmentID,
                        context: $0.context
                    )
                },
            minutes: meeting.minutes.isEmpty ? nil : meeting.minutes,
            privateNotes: options.includePrivateNotes && !notes.isEmpty ? notes : nil,
            notesCaveat: meeting.notesCaveat,
            notesSource: meeting.insightsSource,
            recording: recordingBytes.map { SharedMeeting.Recording(byteCount: $0, fileExtension: "caf") },
            kind: meeting.kind.rawValue
        )
    }

    /// Writes the meeting's file for the share sheet. Big recordings and password protection take a
    /// few seconds, so the writing happens off the main thread.
    @MainActor
    static func makeFile(for meeting: Meeting, options: ShareOptions, sharedBy: String?) async throws -> URL {
        let audioURL = options.includeRecording ? meeting.playableAudioURL : nil
        let shared = document(
            for: meeting,
            options: options,
            sharedBy: sharedBy,
            recordingBytes: audioURL.flatMap(fileSize)
        )
        try? meeting.modelContext?.save()
        let url = shareFolder.appendingPathComponent(fileName(title: meeting.title, date: meeting.createdAt))
        try? FileManager.default.removeItem(at: url)
        let password = options.password
        try await Task.detached(priority: .userInitiated) {
            try MeetingFileFormat.write(shared, audio: audioURL, password: password, to: url)
        }.value
        return url
    }

    /// A short, readable version for people without Clear Notes: the minutes if they've been
    /// written, otherwise the summary, decisions and actions.
    @MainActor
    static func readableText(for meeting: Meeting) -> String {
        if !meeting.minutes.isEmpty { return meeting.minutes }
        var lines = [meeting.title, meeting.createdAt.formatted(date: .long, time: .shortened), ""]
        let summary = NotesText.bullets(from: meeting.summary)
        if !summary.isEmpty {
            lines += ["Summary"] + summary.map { "• \($0)" } + [""]
        }
        if !meeting.decisions.isEmpty {
            lines += ["Decisions"] + meeting.decisions.map { "• \($0)" } + [""]
        }
        let actions = meeting.actions.filter { $0.status == .open || $0.status == .done }
        if !actions.isEmpty {
            lines += ["Actions"] + actions.map { action -> String in
                var line = "• \(action.text)"
                let details = [action.owner, action.due].compactMap { $0 }
                if !details.isEmpty { line += " — " + details.joined(separator: ", ") }
                if let context = action.context { line += ". \(context)" }
                if action.status == .done { line += " (done)" }
                return line
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Importing

    /// Reads a file off the main thread. With `withRecording`, the recording (if any) is unpacked to
    /// a temporary file and checked.
    static func open(_ url: URL, password: String?, withRecording: Bool) async throws -> (meeting: SharedMeeting, recording: URL?) {
        try await Task.detached(priority: .userInitiated) { () throws -> (meeting: SharedMeeting, recording: URL?) in
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let preview = try MeetingFileFormat.read(url, password: password)
            guard withRecording, preview.recording != nil else { return (preview, nil) }
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Import", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let audio = folder.appendingPathComponent(UUID().uuidString + ".caf")
            do {
                let meeting = try MeetingFileFormat.read(url, password: password, writingAudioTo: audio)
                return (meeting, audio)
            } catch {
                try? FileManager.default.removeItem(at: audio)
                throw error
            }
        }.value
    }

    /// A meeting already in Clear Notes that this file is a copy of, if any.
    @MainActor
    static func existingCopy(of shared: SharedMeeting, in context: ModelContext) -> Meeting? {
        let meetings = (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
        // One in Recently deleted doesn't count: importing again adds it afresh.
        return meetings.first { $0.shareID == shared.meetingID && $0.deletedAt == nil }
    }

    /// Adds the shared meeting to Clear Notes, or updates `existing` with it. The recipient's own
    /// notes on an existing copy are kept unless the file brings notes of its own.
    @MainActor
    @discardableResult
    static func importMeeting(
        _ shared: SharedMeeting,
        recording: URL?,
        replacing existing: Meeting?,
        into context: ModelContext
    ) -> Meeting {
        let meeting = existing ?? Meeting(title: shared.title, createdAt: shared.date, duration: shared.duration)
        meeting.title = shared.title
        meeting.createdAt = shared.date
        meeting.duration = shared.duration
        meeting.attendees = shared.invited
        meeting.kind = shared.kind.flatMap(MeetingKind.init(rawValue:)) ?? .meeting
        meeting.speakers = shared.speakers.map { Speaker(id: $0.id, number: $0.number, name: $0.name) }
        meeting.segments = shared.transcript.map {
            TranscriptSegment(id: $0.id, start: $0.start, end: $0.end, text: $0.text, speakerID: $0.speakerID)
        }
        meeting.summary = shared.summary
        meeting.topics = shared.topics.map { Topic(title: $0.title, start: $0.start, end: $0.end, points: $0.points) }
        meeting.decisions = shared.decisions
        meeting.minutes = shared.minutes ?? ""
        meeting.minutesSource = shared.minutes == nil ? nil : "Shared" + (shared.sharedBy.map { " by \($0)" } ?? "")
        meeting.minutesWrittenAt = shared.minutes == nil ? nil : shared.sharedAt
        if let notes = shared.privateNotes {
            meeting.userNotes = notes
        } else if existing == nil {
            meeting.userNotes = ""
        }
        meeting.notesCaveat = shared.notesCaveat
        meeting.insightsSource = shared.notesSource ?? "Shared"
        meeting.processingState = .ready
        meeting.processingStage = nil
        meeting.processingError = nil
        meeting.notesNeedRefresh = false
        meeting.pendingAudioFileName = nil
        meeting.notesProgressData = nil
        meeting.shareID = shared.meetingID
        meeting.sharedBy = shared.sharedBy
        meeting.importedAt = .now
        meeting.revision += 1

        for old in meeting.actions {
            context.delete(old)
        }
        let actions = shared.actions.map { action in
            ActionItem(
                text: action.text,
                owner: action.owner,
                due: action.due,
                context: action.context,
                status: ActionStatus(rawValue: action.status) ?? .open,
                sourceSegmentID: action.sourceLineID
            )
        }
        actions.forEach { context.insert($0) }
        meeting.actions = actions

        if let recording {
            keepRecording(recording, for: meeting)
        }
        if existing == nil {
            context.insert(meeting)
        }
        try? context.save()
        return meeting
    }

    /// Moves an imported recording into place, kept for as long as the recipient's own setting says
    /// (counted from today, not from the meeting).
    @MainActor
    private static func keepRecording(_ temporary: URL, for meeting: Meeting) {
        let retention = AudioRetention.current
        guard retention.keepsAudio else {
            try? FileManager.default.removeItem(at: temporary)
            return
        }
        let name = RecordingStore.newFileName()
        let destination = RecordingStore.url(for: name)
        do {
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            return
        }
        RecordingStore.protect(destination)
        meeting.deleteAudio()
        meeting.audioFileName = name
        meeting.audioExpiresAt = retention.expiry(from: .now)
    }

    /// Files iOS copied into the app to be opened ("Open in Clear Notes") are deleted once they've
    /// been imported or cancelled. Files opened where they are (e.g. from Files) are left alone.
    static func discardIncoming(_ url: URL) {
        guard url.path.contains("/Documents/Inbox/") || url.path.hasPrefix(FileManager.default.temporaryDirectory.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
