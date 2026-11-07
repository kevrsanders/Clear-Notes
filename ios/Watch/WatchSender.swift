import Foundation
import Observation
import WatchConnectivity
import WatchKit

/// Sends finished recordings to the iPhone. WatchConnectivity delivers them in the background
/// when the iPhone is in reach; a recording is removed from the watch once it has arrived.
@MainActor
@Observable
final class WatchSender {
    static let shared = WatchSender()

    /// Recordings on the watch not yet on the iPhone.
    private(set) var waiting = 0
    /// The recording the iPhone is making, if any, which the watch can pause and mark.
    private(set) var phoneRecording: PhoneRecordingState?
    /// Shown briefly after a tap on the remote, e.g. "Action marked".
    private(set) var confirmation: String?
    private(set) var remoteError: String?

    private let delegate = SessionDelegate()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = delegate
        WCSession.default.activate()
        refresh()
    }

    /// Saves the recording's details beside it and sends it.
    func queue(_ audio: URL, info: WatchRecordingInfo) {
        let details = audio.deletingPathExtension().appendingPathExtension("json")
        try? JSONEncoder().encode(info).write(to: details)
        sendWaiting()
    }

    /// Hands every recording that isn't already on its way to WatchConnectivity.
    func sendWaiting() {
        defer { refresh() }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let inFlight = Set(session.outstandingFileTransfers.map { $0.file.fileURL.lastPathComponent })
        for details in WatchStore.waitingDetails() {
            guard let data = try? Data(contentsOf: details),
                  let info = try? JSONDecoder().decode(WatchRecordingInfo.self, from: data)
            else { continue }
            let audio = details.deletingPathExtension().appendingPathExtension("m4a")
            guard FileManager.default.fileExists(atPath: audio.path), !inFlight.contains(audio.lastPathComponent) else { continue }
            session.transferFile(audio, metadata: info.metadata)
        }
    }

    /// A transfer finished: once delivered, the recording is removed from the watch.
    func finished(_ audio: URL, delivered: Bool) {
        if delivered {
            try? FileManager.default.removeItem(at: audio)
            try? FileManager.default.removeItem(at: audio.deletingPathExtension().appendingPathExtension("json"))
        }
        refresh()
    }

    func refresh() {
        waiting = WatchStore.waitingDetails().count
    }

    // MARK: - Remote for the iPhone's recording

    func receive(_ state: PhoneRecordingState?) {
        phoneRecording = state
        if state == nil {
            confirmation = nil
            remoteError = nil
        }
    }

    /// Pause, Resume, Mark action or Mark decision on the iPhone's recording.
    func send(_ command: String, confirm: String) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else {
            remoteError = "Can't reach your iPhone"
            WKInterfaceDevice.current().play(.failure)
            return
        }
        remoteError = nil
        session.sendMessage([PhoneRemote.commandKey: command], replyHandler: { reply in
            let done = reply["ok"] as? Bool ?? false
            Task { @MainActor in WatchSender.shared.commandFinished(done: done, confirm: confirm) }
        }, errorHandler: { _ in
            Task { @MainActor in WatchSender.shared.commandFinished(done: false, confirm: confirm) }
        })
    }

    private func commandFinished(done: Bool, confirm: String) {
        if done {
            confirmation = confirm
            WKInterfaceDevice.current().play(.success)
        } else {
            remoteError = "Your iPhone didn't respond"
            WKInterfaceDevice.current().play(.failure)
        }
    }

    func clearConfirmation() {
        confirmation = nil
    }
}

private final class SessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let context = session.receivedApplicationContext
        let hasState = PhoneRecordingState.isContext(context)
        let state = PhoneRecordingState.from(context)
        Task { @MainActor in
            if hasState { WatchSender.shared.receive(state) }
            WatchSender.shared.sendWaiting()
        }
    }

    /// The iPhone's recording started, changed or stopped.
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard PhoneRecordingState.isContext(applicationContext) else { return }
        let state = PhoneRecordingState.from(applicationContext)
        Task { @MainActor in WatchSender.shared.receive(state) }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard PhoneRecordingState.isContext(message) else { return }
        let state = PhoneRecordingState.from(message)
        Task { @MainActor in WatchSender.shared.receive(state) }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let audio = fileTransfer.file.fileURL
        let delivered = error == nil
        Task { @MainActor in WatchSender.shared.finished(audio, delivered: delivered) }
    }
}
