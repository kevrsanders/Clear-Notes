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
    /// The mark this action was written from, so regenerating the notes doesn't add it twice.
    var markID: UUID?
    /// A short line of detail from what was said around it, e.g. "Priya needs it for Monday's
    /// planning meeting".
    var context: String?
    var meeting: Meeting?

    init(
        text: String,
        owner: String? = nil,
        due: String? = nil,
        context: String? = nil,
        status: ActionStatus = .suggested,
        sourceSegmentID: UUID? = nil
    ) {
        self.text = text
        self.owner = owner
        self.due = due
        self.context = context
        self.statusRaw = status.rawValue
        self.createdAt = .now
        self.sourceSegmentID = sourceSegmentID
    }

    var status: ActionStatus {
        get { ActionStatus(rawValue: statusRaw) ?? .open }
        set { statusRaw = newValue.rawValue }
    }
}
