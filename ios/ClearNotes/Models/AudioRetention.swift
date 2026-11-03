import Foundation

/// How long a meeting's recording stays on the iPhone for playback.
enum AudioRetention: Int, CaseIterable, Identifiable {
    /// Delete as soon as speakers are identified and notes are written.
    case whenNotesReady = 0
    case oneDay = 1
    case oneWeek = 7
    case oneMonth = 30
    case untilDeleted = -1

    static let `default` = AudioRetention.oneWeek

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .whenNotesReady: "Delete when notes are ready"
        case .oneDay: "1 day"
        case .oneWeek: "7 days"
        case .oneMonth: "30 days"
        case .untilDeleted: "Until I delete it"
        }
    }

    var keepsAudio: Bool { self != .whenNotesReady }

    /// When a recording made at `date` should be deleted. Nil means never (or not kept at all).
    func expiry(from date: Date) -> Date? {
        guard rawValue > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: rawValue, to: date)
    }

    /// One line for the consent sheet and settings.
    var promise: String {
        switch self {
        case .whenNotesReady: "Audio is deleted as soon as your notes are ready."
        case .untilDeleted: "The recording stays on this iPhone for playback until you delete it."
        default: "The recording stays on this iPhone for playback, then is deleted after \(title)."
        }
    }

    /// The user's choice, read outside SwiftUI views.
    static var current: AudioRetention {
        let stored = UserDefaults.standard.object(forKey: SettingsKeys.audioRetention) as? Int
        return stored.flatMap(AudioRetention.init(rawValue:)) ?? .default
    }
}
