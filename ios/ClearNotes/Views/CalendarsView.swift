import EventKit
import SwiftUI

/// Settings → Calendar → Choose calendars: which calendars Clear Notes uses. Your main calendar is
/// on; colleagues' shared calendars are off until turned on. Each lists today's events, so it's
/// easy to see where an event like "WFH" comes from.
struct CalendarsView: View {
    private struct CalendarRow: Identifiable {
        var id: String
        var title: String
        var color: Color
        var isOnByDefault: Bool
    }

    private struct AccountGroup: Identifiable {
        var id: String
        var calendars: [CalendarRow]
    }

    @State private var groups: [AccountGroup] = []
    @State private var choices: [String: Bool] = [:]
    /// Today's event titles, keyed by calendar ID.
    @State private var today: [String: [String]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your main calendar is on. Work accounts often include colleagues' shared calendars, and those stay off so their meetings aren't offered as yours. Turn on any others you want, such as a team calendar.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)

                if groups.isEmpty {
                    Text("No calendars found on this iPhone.")
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .cardStyle()
                }

                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(group.id)
                            .padding(.horizontal, 4)
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(group.calendars.enumerated()), id: \.element.id) { index, calendar in
                                if index > 0 { Divider() }
                                row(calendar)
                            }
                        }
                        .cardStyle(padding: 16)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background { ScreenBackground() }
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func row(_ calendar: CalendarRow) -> some View {
        Toggle(isOn: Binding(
            get: { choices[calendar.id] ?? calendar.isOnByDefault },
            set: { isOn in
                choices[calendar.id] = isOn
                CalendarReader.calendarChoices = choices
            }
        )) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Circle()
                    .fill(calendar.color)
                    .frame(width: 11, height: 11)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                    Text(todayText(for: calendar.id))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .tint(Theme.brand)
    }

    private func todayText(for id: String) -> String {
        let titles = today[id] ?? []
        return titles.isEmpty ? "Nothing today" : "Today: " + titles.joined(separator: ", ")
    }

    private func load() {
        let reader = CalendarReader.shared
        let mainID = reader.mainCalendarID
        let calendars = reader.calendars()
        let byAccount = Dictionary(grouping: calendars) { $0.source?.title ?? "Other" }
        // Accounts in the order of their first calendar, so the one with the main calendar comes first.
        var accounts: [String] = []
        for calendar in calendars where !accounts.contains(calendar.source?.title ?? "Other") {
            accounts.append(calendar.source?.title ?? "Other")
        }
        groups = accounts.map { account in
            AccountGroup(id: account, calendars: (byAccount[account] ?? []).map { calendar in
                CalendarRow(
                    id: calendar.calendarIdentifier,
                    title: CalendarChoice.displayName(calendar.title),
                    color: calendar.cgColor.map { Color(cgColor: $0) } ?? Theme.brand,
                    isOnByDefault: reader.isOnByDefault(calendar, mainID: mainID)
                )
            })
        }
        today = Dictionary(grouping: reader.meetingsToday(fromAllCalendars: true)) { $0.calendarID }
            .mapValues { events in events.map { $0.title.isEmpty ? "Untitled" : $0.title } }
        choices = CalendarReader.calendarChoices
    }
}
