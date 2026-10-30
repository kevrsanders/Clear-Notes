import Foundation

/// Temporary audio files kept only until speaker separation has run.
/// Stored in Application Support, excluded from backups, and encrypted while the iPhone is locked.
enum RecordingStore {
    static var directory: URL {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PendingAudio", isDirectory: true)
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

    static func newFileName() -> String {
        UUID().uuidString + ".caf"
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Keeps the file readable while it is open (so recording continues with the screen locked).
    static func protect(_ url: URL) {
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUnlessOpen], ofItemAtPath: url.path)
    }

    static func delete(_ fileName: String?) {
        guard let fileName else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// Removes audio that no meeting is waiting for, e.g. after the app was closed mid-recording.
    static func deleteOrphans(keeping fileNames: Set<String>) {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        for file in files where !fileNames.contains(file) {
            delete(file)
        }
    }
}
