import Foundation
import SwiftData
import WatchConnectivity

extension Notification.Name {
    /// A recording from Apple Watch is waiting in the inbox to be added.
    static let watchRecordingArrived = Notification.Name("ClearNotes.watchRecordingArrived")
}

/// Receives recordings made on Apple Watch. The file goes straight into the inbox (iOS removes it
/// once the delivery call returns), and Clear Notes adds it as a meeting when it's next running.
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        guard let info = WatchRecordingInfo(metadata: file.metadata) else { return }
        guard WatchInbox.accept(file.fileURL, info: info) else { return }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .watchRecordingArrived, object: nil)
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// After switching to another watch, the session is activated again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
}

/// Recordings from Apple Watch waiting to become meetings: each is an audio file with its details
/// beside it. Kept on this iPhone only, protected and left out of backups.
enum WatchInbox {
    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WatchInbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUnlessOpen]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var excluded = url
            try? excluded.setResourceValues(values)
        }
        return url
    }

    /// Moves a delivered file into the inbox with its details. Called during the delivery.
    static func accept(_ fileURL: URL, info: WatchRecordingInfo) -> Bool {
        let fileExtension = fileURL.pathExtension.isEmpty ? "m4a" : fileURL.pathExtension
        let audio = directory.appendingPathComponent("\(info.id.uuidString).\(fileExtension)")
        let details = directory.appendingPathComponent("\(info.id.uuidString).json")
        do {
            try? FileManager.default.removeItem(at: audio)
            try FileManager.default.moveItem(at: fileURL, to: audio)
            try JSONEncoder().encode(info).write(to: details, options: .completeFileProtectionUnlessOpen)
            return true
        } catch {
            try? FileManager.default.removeItem(at: audio)
            return false
        }
    }

    /// Adds every waiting recording as a meeting and starts processing it. Returns how many.
    @MainActor
    @discardableResult
    static func importAll(into context: ModelContext) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var added = 0
        for details in files where details.pathExtension == "json" {
            guard let data = try? Data(contentsOf: details),
                  let info = try? JSONDecoder().decode(WatchRecordingInfo.self, from: data),
                  let audio = files.first(where: {
                      $0.deletingPathExtension().lastPathComponent == info.id.uuidString && $0.pathExtension != "json"
                  })
            else { continue }
            let fileName = "\(info.id.uuidString).\(audio.pathExtension)"
            let destination = RecordingStore.url(for: fileName)
            do {
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: audio, to: destination)
            } catch {
                continue
            }
            RecordingStore.protect(destination)
            try? FileManager.default.removeItem(at: details)

            let event = info.eventID.flatMap { id in
                CalendarReader.shared.meetingsToday(around: info.startedAt).first { $0.id == id }
            }
            let meeting = makeMeeting(from: info, audioFileName: fileName, event: event)
            context.insert(meeting)
            try? context.save()
            added += 1
            Task { await MeetingProcessor.process(meeting) }
        }
        return added
    }

    /// The meeting for a recording from the watch: transcribed from its audio first, then
    /// processed like any other.
    static func makeMeeting(from info: WatchRecordingInfo, audioFileName: String, event: CalendarMeeting?) -> Meeting {
        let kind: MeetingKind = switch info.kind {
        case .voiceNote: .voiceNote
        case .catchUp: .catchUp
        case .meeting: .meeting
        }
        let meeting = Meeting(
            title: Meeting.defaultTitle(for: info.startedAt, kind: kind),
            createdAt: info.startedAt,
            duration: info.duration,
            // Kept in the processing slot until it's transcribed, whatever the keep setting.
            pendingAudioFileName: audioFileName
        )
        meeting.kind = kind
        meeting.recordedOnWatch = true
        meeting.transcribeFromAudio = true
        meeting.marks = info.marks.map { MeetingMark(kind: .action, time: $0) }
        if kind == .catchUp {
            meeting.expectedSpeakers = 2
        }
        if let event {
            meeting.link(to: event)
        } else if kind == .meeting, let title = info.eventTitle, !title.isEmpty {
            meeting.title = title
        }
        return meeting
    }
}
