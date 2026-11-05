import BackgroundTasks
import Foundation

/// On iOS 26, lets a meeting's processing carry on after the user leaves Clear Notes, with its
/// progress shown by the system (like a download) where the user can also stop it.
///
/// iOS decides how long it may run. Apple Intelligence may still decline to write notes in the
/// background; then the notes pause, their finished parts are kept, and they carry on from where
/// they stopped when Clear Notes is next opened. On earlier iOS versions this does nothing.
@MainActor
final class ContinuedProcessing {
    static let shared = ContinuedProcessing()

    /// Identifiers must start with this, matching `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
    nonisolated static var identifierPrefix: String {
        (Bundle.main.bundleIdentifier ?? "com.clearnotes.app") + ".notes."
    }

    /// Unit tests process meetings too; they shouldn't start system background work.
    private static let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// The running system task, stored untyped because its type only exists on iOS 26.
    private var task: AnyObject?
    /// When a request was submitted whose task hasn't started yet. iOS can drop a request without
    /// starting it, so after half a minute another may be submitted.
    private var pendingSince: Date?
    private var isPending: Bool {
        pendingSince.map { Date().timeIntervalSince($0) < 30 } ?? false
    }
    /// The latest progress, applied when the task starts.
    private var fraction = 0.0
    private var subtitle = "Starting"
    enum Outcome {
        case done, paused, waitingForUnlock, failed
    }

    /// How the work ended, when it ended before the system started the task.
    private var endedEarly: Outcome?

    /// Asks iOS to let the work continue in the background. Call it while Clear Notes is on screen,
    /// as a result of something the user did, e.g. finishing a recording.
    func begin() {
        guard #available(iOS 26.0, *) else { return }
        guard task == nil, !isPending, !Self.isRunningTests else { return }
        // Each request has its own identifier: iOS ends the app if one is registered twice.
        let identifier = Self.identifierPrefix + UUID().uuidString
        let scheduler = BGTaskScheduler.shared
        let registered = scheduler.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let continued = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in ContinuedProcessing.shared.started(continued) }
        }
        guard registered else { return }
        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Preparing meeting notes",
            subtitle: subtitle
        )
        // Only useful if it can start now, while the user is leaving the app.
        request.strategy = .fail
        do {
            try scheduler.submit(request)
            pendingSince = Date()
            endedEarly = nil
        } catch {
            // Not available right now (e.g. too many tasks running). Processing carries on as before.
        }
    }

    /// Shows how far the meeting has got.
    func update(_ meeting: Meeting) {
        fraction = ProcessingProgress.fraction(
            stage: meeting.processingStage,
            partsDone: meeting.notesPartsDone,
            partsTotal: meeting.notesPartsTotal
        )
        subtitle = ProcessingProgress.subtitle(
            stage: meeting.processingStage,
            partsDone: meeting.notesPartsDone,
            partsTotal: meeting.notesPartsTotal
        )
        guard #available(iOS 26.0, *), let task = task as? BGContinuedProcessingTask else { return }
        apply(to: task)
    }

    /// Ends the system's progress view: finished, paused until Clear Notes is opened, or failed.
    func finish(_ outcome: Outcome) {
        guard #available(iOS 26.0, *) else { return }
        guard let task = task as? BGContinuedProcessingTask else {
            if isPending { endedEarly = outcome }
            return
        }
        complete(task, outcome)
    }

    @available(iOS 26.0, *)
    private func started(_ started: BGContinuedProcessingTask) {
        pendingSince = nil
        if let outcome = endedEarly {
            endedEarly = nil
            complete(started, outcome)
            return
        }
        guard task == nil else {
            // A request that started late, after another took over. One progress view is enough.
            started.setTaskCompleted(success: true)
            return
        }
        task = started
        started.expirationHandler = {
            // iOS needs the time back, or the user stopped it. The work itself carries on while the
            // app is allowed to run, and otherwise when Clear Notes is next opened.
            Task { @MainActor in
                let shared = ContinuedProcessing.shared
                guard let current = shared.task as? BGContinuedProcessingTask, current === started else { return }
                shared.task = nil
                current.setTaskCompleted(success: false)
            }
        }
        started.progress.totalUnitCount = 100
        apply(to: started)
    }

    @available(iOS 26.0, *)
    private func apply(to task: BGContinuedProcessingTask) {
        task.progress.completedUnitCount = Int64((fraction * 100).rounded())
        task.updateTitle(task.title, subtitle: subtitle)
    }

    @available(iOS 26.0, *)
    private func complete(_ task: BGContinuedProcessingTask, _ outcome: Outcome) {
        if self.task === task { self.task = nil }
        switch outcome {
        case .done:
            task.progress.completedUnitCount = task.progress.totalUnitCount
            task.updateTitle(task.title, subtitle: "Notes ready")
        case .paused:
            task.updateTitle(task.title, subtitle: "Paused · open Clear Notes to continue")
        case .waitingForUnlock:
            task.updateTitle(task.title, subtitle: "Paused · unlock your iPhone to continue")
        case .failed:
            task.updateTitle(task.title, subtitle: "Couldn't finish · open Clear Notes")
        }
        task.setTaskCompleted(success: outcome == .done)
    }
}
