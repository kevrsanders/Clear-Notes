import Foundation

/// Plain Markdown version of a meeting for sharing by email, Teams or Notes.
enum MarkdownExporter {
    static func markdown(for meeting: Meeting) -> String {
        var lines: [String] = [
            "# \(meeting.title)",
            "",
            "\(meeting.createdAt.formatted(date: .long, time: .shortened)) · \(meeting.duration.durationString)",
            "",
        ]

        if !meeting.summary.isEmpty {
            lines += ["## Summary", "", meeting.summary, ""]
        }
        if !meeting.decisions.isEmpty {
            lines += ["## Decisions", ""] + meeting.decisions.map { "- \($0)" } + [""]
        }

        let actions = meeting.actions
            .filter { $0.status == .open || $0.status == .done }
            .sorted { $0.createdAt < $1.createdAt }
        if !actions.isEmpty {
            lines += ["## Actions", ""]
            lines += actions.map { action in
                var line = "- [\(action.status == .done ? "x" : " ")] \(action.text)"
                let details = [action.owner, action.due].compactMap { $0 }
                if !details.isEmpty { line += " (\(details.joined(separator: ", ")))" }
                return line
            }
            lines.append("")
        }

        if !meeting.userNotes.isEmpty {
            lines += ["## My notes", "", meeting.userNotes, ""]
        }
        if !meeting.segments.isEmpty {
            lines += ["## Transcript", ""]
            lines += meeting.segments.map { "**[\($0.start.clockString)]** \($0.text)" }
        }
        return lines.joined(separator: "\n")
    }
}
