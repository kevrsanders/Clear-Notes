import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum FollowUpKind: String, CaseIterable, Identifiable {
    case actionList, email, projectPlan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .actionList: "List actions"
        case .email: "Write follow-up email"
        case .projectPlan: "Draft project plan"
        }
    }

    var subtitle: String {
        switch self {
        case .actionList: "Owners and due dates, ready to paste"
        case .email: "A thank-you with decisions and next steps"
        case .projectPlan: "Goals, workstreams and timeline"
        }
    }

    var systemImage: String {
        switch self {
        case .actionList: "checklist"
        case .email: "envelope"
        case .projectPlan: "doc.text"
        }
    }
}

/// The parts of a meeting a follow-up needs, copied off the main actor.
struct MeetingSnapshot: Sendable {
    struct Action: Sendable {
        var text: String
        var owner: String?
        var due: String?
        var isDone: Bool
    }

    var title: String
    var date: Date
    var summary: String
    var decisions: [String]
    var topics: [Topic]
    var actions: [Action]
    var people: [String]
}

extension MeetingSnapshot {
    @MainActor
    init(_ meeting: Meeting) {
        self.init(
            title: meeting.title,
            date: meeting.createdAt,
            summary: meeting.summary,
            decisions: meeting.decisions,
            topics: meeting.topics,
            // Accepted actions only: suggestions haven't been checked by a person yet.
            actions: meeting.actions
                .filter { $0.status == .open || $0.status == .done }
                .sorted { $0.createdAt < $1.createdAt }
                .map { Action(text: $0.text, owner: $0.owner, due: $0.due, isDone: $0.status == .done) },
            people: meeting.speakers.compactMap(\.name)
        )
    }
}

struct FollowUpDraft: Sendable {
    var text: String
    /// Shown under the title so the user knows how the draft was made.
    var source: String
}

/// Writes follow-ups from a meeting. Templates are built from the meeting's own notes, so
/// nothing is invented; on iPhones with Apple Intelligence the email and plan are then
/// rewritten into natural prose on the device, keeping the same facts.
enum FollowUpWriter {
    static func draft(_ kind: FollowUpKind, for meeting: MeetingSnapshot) async -> FollowUpDraft {
        let base = template(kind, for: meeting)
        guard kind != .actionList else {
            return FollowUpDraft(text: base, source: "From your accepted actions")
        }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), AppleIntelligenceEnhancer.isAvailable,
           let rewritten = try? await rewrite(base, kind: kind) {
            return FollowUpDraft(text: rewritten, source: "Written on this iPhone by Apple Intelligence")
        }
        #endif
        return FollowUpDraft(text: base, source: "From your meeting notes")
    }

    // MARK: - Templates

    static func template(_ kind: FollowUpKind, for meeting: MeetingSnapshot) -> String {
        switch kind {
        case .actionList: actionList(meeting)
        case .email: email(meeting)
        case .projectPlan: projectPlan(meeting)
        }
    }

    static func actionList(_ meeting: MeetingSnapshot) -> String {
        var lines = ["Actions from \(meeting.title) (\(meeting.date.formatted(date: .abbreviated, time: .omitted)))", ""]
        let open = meeting.actions.filter { !$0.isDone }
        if open.isEmpty {
            lines.append("No open actions.")
        } else {
            lines += open.map { action in
                var line = "☐ \(action.text)"
                let details = [action.owner, action.due].compactMap { $0 }
                if !details.isEmpty { line += " — \(details.joined(separator: ", "))" }
                return line
            }
        }
        let done = meeting.actions.filter(\.isDone)
        if !done.isEmpty {
            lines += ["", "Done:"] + done.map { "☑ \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }

    static func email(_ meeting: MeetingSnapshot) -> String {
        var lines = [
            "Subject: Follow-up: \(meeting.title)",
            "",
            "Hi all,",
            "",
            "Thanks for your time on \(meeting.date.formatted(.dateTime.weekday(.wide).day().month(.wide))). Here's a quick summary.",
        ]
        let summary = bullets(meeting.summary)
        if !summary.isEmpty {
            lines += ["", "Summary"] + summary.map { "• \($0)" }
        }
        if !meeting.decisions.isEmpty {
            lines += ["", "What we agreed"] + meeting.decisions.map { "• \($0)" }
        }
        let open = meeting.actions.filter { !$0.isDone }
        if !open.isEmpty {
            lines += ["", "Next steps"] + open.map { action in
                let owner = action.owner.map { "\($0): " } ?? ""
                let due = action.due.map { " (\($0.lowercased()))" } ?? ""
                return "• \(owner)\(action.text)\(due)"
            }
        }
        lines += ["", "Let me know if I've missed anything.", "", "Best wishes"]
        return lines.joined(separator: "\n")
    }

    static func projectPlan(_ meeting: MeetingSnapshot) -> String {
        var lines = ["Project plan: \(meeting.title)", ""]
        let summary = bullets(meeting.summary)
        lines += ["Goal", summary.first ?? meeting.title, ""]
        if !meeting.decisions.isEmpty {
            lines += ["Decisions so far"] + meeting.decisions.map { "• \($0)" } + [""]
        }

        let open = meeting.actions.filter { !$0.isDone }
        if !open.isEmpty {
            lines.append("Workstreams")
            let byOwner = Dictionary(grouping: open) { $0.owner ?? "Unassigned" }
            for owner in byOwner.keys.sorted(by: { ($0 == "Unassigned" ? "~" : $0) < ($1 == "Unassigned" ? "~" : $1) }) {
                lines.append(owner)
                lines += (byOwner[owner] ?? []).map { "  • \($0.text)" }
            }
            lines.append("")
        }

        let dated = open.filter { $0.due != nil }
        if !dated.isEmpty {
            lines += ["Timeline"] + dated.map { "• \($0.due ?? ""): \($0.text)" } + [""]
        }
        if !meeting.topics.isEmpty {
            lines += ["Areas discussed"] + meeting.topics.map { "• \($0.title)" } + [""]
        }
        lines += ["Open questions", "• "]
        return lines.joined(separator: "\n")
    }

    /// Summary lines without their "- " bullet markers.
    private static func bullets(_ summary: String) -> [String] {
        summary
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix("- ") || $0.hasPrefix("• ") ? String($0.dropFirst(2)) : $0 }
            .filter { !$0.isEmpty }
    }

    // MARK: - On-device rewrite

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    private static func rewrite(_ base: String, kind: FollowUpKind) async throws -> String {
        let instructions = """
            You rewrite meeting follow-ups so they read naturally. Keep every fact, name, date and action \
            exactly as given. Do not add facts, people, dates or tasks that are not in the draft. \
            Keep it short and use plain British English.
            """
        let request = switch kind {
        case .email:
            "Rewrite this draft as a warm, concise follow-up email. Keep the Subject line first and keep the bullet lists.\n\n\(base)"
        case .projectPlan:
            "Tidy this draft project plan. Keep the headings and bullets, and write the Goal as one clear sentence.\n\n\(base)"
        case .actionList:
            base
        }
        let session = LanguageModelSession(instructions: instructions)
        let text = try await session.respond(to: request).content
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    #endif
}
