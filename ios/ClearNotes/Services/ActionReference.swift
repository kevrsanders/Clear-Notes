import Foundation
import SwiftData

/// Action references such as WCI-3: the meeting's initials and the action's number in it.
enum ActionReference {
    /// Words left out of initials.
    static let smallWords: Set<String> = [
        "a", "an", "and", "the", "of", "for", "with", "to", "on", "in", "at", "by", "or", "re", "&", "+",
    ]

    /// The prefix for a meeting's actions: its title's initials. A catch-up named by Clear Notes
    /// uses the other person's initials ("TE" for a catch-up with Tom Ellis), and a title Clear
    /// Notes gave from the date uses the type: MTG, CU or VN.
    static func prefix(for meeting: Meeting) -> String {
        if let person = meeting.catchUpPerson, meeting.title == Meeting.catchUpTitle(with: person) {
            return prefix(forTitle: person) ?? "CU"
        }
        if meeting.hasDefaultTitle { return kindPrefix(meeting.kind) }
        return prefix(forTitle: meeting.title) ?? kindPrefix(meeting.kind)
    }

    static func kindPrefix(_ kind: MeetingKind) -> String {
        switch kind {
        case .meeting: "MTG"
        case .catchUp: "CU"
        case .voiceNote: "VN"
        }
    }

    /// "Weekly check-in" → "WCI", "Budget review" → "BR", "Standup" → "STA": the first letter of
    /// each word (and of each part of a hyphenated one), at most four, or the first three letters
    /// of a single word. Nil when the title has no letters.
    static func prefix(forTitle title: String) -> String? {
        let words = title
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !smallWords.contains($0.lowercased()) }
            .flatMap { word in word.split(separator: "-").map(String.init) }
            .map { word in word.filter(\.isLetter) }
            .filter { !$0.isEmpty }
        guard let first = words.first else { return nil }
        if words.count == 1 {
            return String(first.prefix(3)).uppercased()
        }
        return String(words.prefix(4).compactMap(\.first)).uppercased()
    }

    /// Numbers the accepted actions of meetings from before references, once, at launch.
    @MainActor
    static func numberExistingActions(in context: ModelContext) {
        let descriptor = FetchDescriptor<Meeting>()
        var changed = false
        for meeting in (try? context.fetch(descriptor)) ?? [] {
            let needsNumbers = meeting.actions.contains { $0.number == nil && ($0.status == .open || $0.status == .done) }
            guard needsNumbers else { continue }
            meeting.numberActions()
            changed = true
        }
        if changed { try? context.save() }
    }
}
