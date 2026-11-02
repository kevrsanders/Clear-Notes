import EventKit
import Foundation

/// A calendar event reduced to what Clear Notes uses: title, times, who was invited and the Teams link.
struct CalendarMeeting: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay = false
    /// Cancelled, or declined by the user.
    var isCancelledOrDeclined = false
    /// Invited people's names, without the user, rooms or resources.
    var attendees: [String] = []
    var teamsJoinURL: URL?

    /// "10:00–11:00"
    var timeRange: String {
        "\(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))"
    }
}

/// Picks the meeting a recording belongs to.
enum CalendarMeetingPicker {
    /// The meeting happening at `date`: one in progress, or one starting within `lookahead`.
    /// When meetings overlap, the one that starts nearest to `date` wins, so starting a recording
    /// just before a back-to-back meeting picks the next meeting, not the one ending.
    static func current(in meetings: [CalendarMeeting], at date: Date, lookahead: TimeInterval = 10 * 60) -> CalendarMeeting? {
        meetings
            .filter { usable($0) && $0.start <= date.addingTimeInterval(lookahead) && $0.end > date }
            .min { first, second in
                let firstGap = abs(first.start.timeIntervalSince(date))
                let secondGap = abs(second.start.timeIntervalSince(date))
                if firstGap != secondGap { return firstGap < secondGap }
                return first.attendees.count > second.attendees.count
            }
    }

    /// The next meeting later the same day, after any meeting happening now.
    static func next(in meetings: [CalendarMeeting], after date: Date, calendar: Calendar = .current) -> CalendarMeeting? {
        meetings
            .filter { usable($0) && $0.start > date && calendar.isDate($0.start, inSameDayAs: date) }
            .min { $0.start < $1.start }
    }

    private static func usable(_ meeting: CalendarMeeting) -> Bool {
        !meeting.isAllDay && !meeting.isCancelledOrDeclined && meeting.end > meeting.start
    }
}

/// Turns directory names and email addresses into everyday names.
enum PersonName {
    /// "SMITH, Jane (Example Trust)" → "Jane Smith"; "jane.smith@example.org" → "Jane Smith".
    static func display(name: String?, email: String? = nil) -> String? {
        if let name = cleaned(name), !name.contains("@") {
            return name
        }
        return fromEmail(email ?? name)
    }

    private static func cleaned(_ raw: String?) -> String? {
        guard var name = raw else { return nil }
        // Drop organisation or role in brackets: "(Example Trust)", "[Contractor]".
        name = name.replacingOccurrences(of: #"\s*[\(\[][^\)\]]*[\)\]]"#, with: "", options: .regularExpression)
        name = name.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
        // "Surname, First" → "First Surname"
        let parts = name.split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2 {
            name = "\(parts[1]) \(parts[0])"
        }
        let words = name.split(whereSeparator: \.isWhitespace).map { word in
            isShouted(word) ? titleCased(word) : String(word)
        }
        let result = words.joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    private static func fromEmail(_ raw: String?) -> String? {
        guard let raw, let local = raw.split(separator: "@").first else { return nil }
        let words = local
            .split(whereSeparator: { ".-_+".contains($0) })
            .map { $0.filter(\.isLetter) }
            .filter { !$0.isEmpty }
            .map { titleCased(Substring($0)) }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    /// All capitals and longer than an initial, e.g. "SMITH".
    private static func isShouted(_ word: Substring) -> Bool {
        let letters = word.filter(\.isLetter)
        return letters.count > 1 && letters == letters.uppercased()
    }

    /// "SMITH-JONES" → "Smith-Jones", "O'BRIEN" → "O'Brien".
    private static func titleCased(_ word: Substring) -> String {
        var result = ""
        var startOfPart = true
        for character in word {
            result += startOfPart ? character.uppercased() : character.lowercased()
            startOfPart = "-'’".contains(character)
        }
        return result
    }
}

/// Finds the Teams join link in an invite, kept for importing the Teams transcript later.
enum TeamsLink {
    private static let pattern = try? NSRegularExpression(
        pattern: #"https://teams\.(microsoft|live)\.com/(l/meetup-join|meet)/[^\s<>"]+"#,
        options: [.caseInsensitive]
    )

    static func find(in texts: [String?]) -> URL? {
        for text in texts.compactMap({ $0 }) {
            let range = NSRange(text.startIndex..., in: text)
            guard let match = pattern?.firstMatch(in: text, range: range),
                  let matchRange = Range(match.range, in: text)
            else { continue }
            let link = String(text[matchRange]).trimmingCharacters(in: CharacterSet(charactersIn: ").,;]>"))
            if let url = URL(string: link) { return url }
        }
        return nil
    }
}

/// Matches an action owner the AI wrote, e.g. "Priya", to a full name from the meeting.
enum OwnerMatcher {
    /// Speaker names are checked first so owners keep their speaker's colour. Then invited people,
    /// by full name or by a first name that only one of them has.
    static func match(_ owner: String, speakers: [String], attendees: [String]) -> String {
        let key = owner.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return owner }
        if let speaker = speakers.first(where: { $0.lowercased() == key }) { return speaker }
        if let attendee = attendees.first(where: { $0.lowercased() == key }) { return attendee }
        guard !key.contains(" ") else { return owner }
        let byFirstName = attendees.filter { $0.split(separator: " ").first?.lowercased() == key }
        return byFirstName.count == 1 ? byFirstName[0] : owner
    }
}

/// Reads today's events from the calendars in Apple's Calendar app, after the user allows it.
/// Nothing is written to the calendar and nothing leaves the iPhone.
@MainActor
final class CalendarReader {
    static let shared = CalendarReader()
    private var store = EKEventStore()

    nonisolated static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    nonisolated static var hasAccess: Bool { status == .fullAccess }
    /// The user has answered the permission prompt, either way.
    nonisolated static var hasAnswered: Bool { status != .notDetermined }
    /// The user said no, or a policy blocks it. Only iOS Settings can change this.
    nonisolated static var isBlocked: Bool { status == .denied || status == .restricted || status == .writeOnly }

    /// Asks once. iOS remembers the answer, so later calls return straight away.
    func requestAccess() async -> Bool {
        let granted = (try? await store.requestFullAccessToEvents()) ?? false
        // A store created before access was granted doesn't see events.
        if granted { store = EKEventStore() }
        return granted
    }

    /// Today's meetings around `date`, oldest first.
    func meetingsToday(around date: Date = .now, calendar: Calendar = .current) -> [CalendarMeeting] {
        guard Self.hasAccess else { return [] }
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? date.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: dayStart, end: dayEnd, calendars: nil)
        return store.events(matching: predicate)
            .map(CalendarMeeting.init(event:))
            .sorted { $0.start < $1.start }
    }

    /// The meeting happening now, if the user has turned on Use my calendar.
    func currentMeeting(at date: Date = .now) -> CalendarMeeting? {
        guard UserDefaults.standard.bool(forKey: SettingsKeys.useCalendar) else { return nil }
        return CalendarMeetingPicker.current(in: meetingsToday(around: date), at: date)
    }
}

extension CalendarMeeting {
    init(event: EKEvent) {
        let participants = ([event.organizer].compactMap { $0 }) + (event.attendees ?? [])
        let me = participants.first(where: \.isCurrentUser)
        var seen = Set<String>()
        let people = participants
            .filter { !$0.isCurrentUser && ($0.participantType == .person || $0.participantType == .unknown) }
            .compactMap { PersonName.display(name: $0.name, email: Self.email(of: $0)) }
            .filter { seen.insert($0.lowercased()).inserted }

        self.init(
            id: "\(event.calendarItemIdentifier)-\(Int(event.startDate.timeIntervalSince1970))",
            title: (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            isCancelledOrDeclined: event.status == .canceled || me?.participantStatus == .declined,
            attendees: people,
            teamsJoinURL: TeamsLink.find(in: [event.url?.absoluteString, event.location, event.notes])
        )
    }

    private static func email(of participant: EKParticipant) -> String? {
        let link = participant.url.absoluteString
        guard link.lowercased().hasPrefix("mailto:") else { return nil }
        return String(link.dropFirst("mailto:".count)).removingPercentEncoding
    }
}
