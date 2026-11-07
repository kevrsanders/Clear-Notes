import AVFoundation
import Foundation
import Observation
import WatchKit

/// Records on the watch's microphone: good for one voice close by (a voice note) or a quick
/// catch-up. The finished file goes to the iPhone, which transcribes it.
@MainActor
@Observable
final class WatchRecorder {
    static let shared = WatchRecorder()

    /// The diary meeting a reminder was for.
    struct Reminder: Equatable {
        var eventID: String?
        var title: String?
    }

    private(set) var isRecording = false
    private(set) var kind: WatchRecordingInfo.Kind = .voiceNote
    private(set) var marks: [TimeInterval] = []
    private(set) var reminder: Reminder?
    /// A reminder that was tapped (rather than Record), offered at the top of the start screen.
    var offered: Reminder?
    private(set) var errorMessage: String?
    /// When the last recording finished, for "Sent to iPhone".
    private(set) var lastFinished: Date?

    private var recorder: AVAudioRecorder?
    private var recordingID = UUID()
    private var fileURL: URL?
    private var startedAt: Date?

    /// What the start screen records: the last choice, voice note at first.
    var preferredKind: WatchRecordingInfo.Kind {
        get { WatchRecordingInfo.Kind(rawValue: UserDefaults.standard.string(forKey: "preferredKind") ?? "") ?? .voiceNote }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "preferredKind") }
    }

    var elapsed: TimeInterval {
        recorder?.currentTime ?? 0
    }

    /// The microphone level, 0 to 1, for the moving bar.
    func level() -> Double {
        guard let recorder, recorder.isRecording else { return 0 }
        recorder.updateMeters()
        let decibels = Double(recorder.averagePower(forChannel: 0))
        return max(0, min(1, (decibels + 50) / 50))
    }

    func startFromWatchFace() async {
        await start(preferredKind)
    }

    func start(_ kind: WatchRecordingInfo.Kind, reminder: Reminder? = nil) async {
        guard !isRecording else { return }
        errorMessage = nil
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Allow the microphone for Clear Notes in Settings on your watch."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            let id = UUID()
            let url = WatchStore.outbox.appendingPathComponent("\(id.uuidString).m4a")
            // Speech at 16 kHz in AAC: small to send, and what the transcribers work at.
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 48_000,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = true
            guard recorder.record() else {
                errorMessage = "The recording couldn't start. Try again."
                try? session.setActive(false)
                return
            }
            self.recorder = recorder
            recordingID = id
            fileURL = url
            startedAt = .now
            marks = []
            self.kind = kind
            self.reminder = reminder
            offered = nil
            isRecording = true
            WKInterfaceDevice.current().play(.start)
        } catch {
            errorMessage = "The recording couldn't start. \(error.localizedDescription)"
            try? AVAudioSession.sharedInstance().setActive(false)
        }
    }

    /// A to-do (voice note) or action (otherwise), just after it was said.
    func mark() {
        guard let recorder, isRecording else { return }
        marks.append(recorder.currentTime)
        WKInterfaceDevice.current().play(.click)
    }

    func stop() {
        guard isRecording, let recorder, let fileURL, let startedAt else { return }
        let duration = recorder.currentTime
        recorder.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        self.recorder = nil
        isRecording = false
        WKInterfaceDevice.current().play(.stop)

        let info = WatchRecordingInfo(
            id: recordingID,
            kind: kind,
            startedAt: startedAt,
            duration: duration,
            marks: marks,
            eventID: reminder?.eventID,
            eventTitle: reminder?.title
        )
        if kind != .meeting {
            preferredKind = kind
        }
        reminder = nil
        lastFinished = .now
        WatchSender.shared.queue(fileURL, info: info)
    }
}

/// Recordings on the watch waiting to reach the iPhone: each audio file with its details beside it.
enum WatchStore {
    static var outbox: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Outbox", isDirectory: true)
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }

    /// The details files of recordings not yet delivered.
    static func waitingDetails() -> [URL] {
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
    }
}
