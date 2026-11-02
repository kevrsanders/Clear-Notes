import Foundation
import SwiftData

enum ActionStatus: String, Codable, CaseIterable {
    /// Suggested by AI and waiting for the user to accept or dismiss it.
    case suggested
    case open
    case done
    case dismissed
}

@Model
final class ActionItem {
    var text: String
    var owner: String?
    var due: String?
    var statusRaw: String
    var createdAt: Date
    /// The transcript segment that supports this action, so the user can check it.
    var sourceSegmentID: UUID?
    var meeting: Meeting?

    init(
        text: String,
        owner: String? = nil,
        due: String? = nil,
        status: ActionStatus = .suggested,
        sourceSegmentID: UUID? = nil
    ) {
        self.text = text
        self.owner = owner
        self.due = due
        self.statusRaw = status.rawValue
        self.createdAt = .now
        self.sourceSegmentID = sourceSegmentID
    }

    var status: ActionStatus {
        get { ActionStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
}
