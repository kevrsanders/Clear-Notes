import SwiftUI

extension MeetingKind {
    var systemImage: String {
        switch self {
        case .meeting: "person.2.fill"
        case .catchUp: "bubble.left.and.bubble.right.fill"
        case .voiceNote: "mic.fill"
        }
    }

    var tint: Color {
        switch self {
        case .meeting: Theme.brand
        case .catchUp: Theme.catchUp
        case .voiceNote: Theme.voiceNote
        }
    }

    /// One line on the Record sheet saying what each type gives you.
    var recordHint: String {
        switch self {
        case .meeting: "A meeting that isn't in your diary. Full notes and minutes."
        case .catchUp: "A chat with one or two people. Short notes: what you covered, what was agreed, and actions."
        case .voiceNote: "Just you. A tidy note and your to-dos. No speaker step, so it's ready sooner."
        }
    }
}

extension Meeting {
    /// The type badge's symbol: a calendar for meetings from the diary.
    var kindSymbol: String { isFromDiary ? "calendar" : kind.systemImage }
    var kindLabel: String { isFromDiary ? "Diary meeting" : kind.title }
}

/// A small rounded square showing what was recorded, as on meeting cards.
struct KindBadge: View {
    let meeting: Meeting
    var size: CGFloat = 24

    var body: some View {
        IconTile(systemName: meeting.kindSymbol, tint: meeting.kind.tint, size: size)
            .accessibilityLabel(meeting.kindLabel)
    }
}
