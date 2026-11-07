import Foundation
import Observation
import WatchConnectivity

/// Sends finished recordings to the iPhone. WatchConnectivity delivers them in the background
/// when the iPhone is in reach; a recording is removed from the watch once it has arrived.
@MainActor
@Observable
final class WatchSender {
    static let shared = WatchSender()

    /// Recordings on the watch not yet on the iPhone.
    private(set) var waiting = 0

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
}

private final class SessionDelegate: NSObject, WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in WatchSender.shared.sendWaiting() }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let audio = fileTransfer.file.fileURL
        let delivered = error == nil
        Task { @MainActor in WatchSender.shared.finished(audio, delivered: delivered) }
    }
}
