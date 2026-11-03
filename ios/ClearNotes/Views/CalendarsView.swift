import EventKit
import SwiftUI

/// Settings → Calendar → Calendars: choose which calendars Clear Notes uses. Each calendar lists
/// today's events, so it's easy to see where an event like "WFH" comes from.
struct CalendarsView: View {
    private struct CalendarRow: Identifiable {
        var id: String
        var title: String
        var color: Color
    }

    private struct AccountGroup: Identifiable {
        var id: String
        var calendars: [CalendarRow]
    }

    @State private var groups: [AccountGroup] = []
    @State private var hidden: Set<String> = []
    /// Today's event titles, keyed by calendar ID.
    @State private var today: [String: [String]] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Turn off calendars that aren't your meetings, such as a family calendar or one shared with you. Calendars hidden in Apple's Calendar app are still listed here, so turn them off here too.")
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
        .background { GlowBackground() }
        .navigationTitle("Calendars")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
    }

    private func row(_ calendar: CalendarRow) -> some View {
        Toggle(isOn: Binding(
            get: { !hidden.contains(calendar.id) },
            set: { isOn in
                if isOn {
                    hidden.remove(calendar.id)
                } else {
                    hidden.insert(calendar.id)
                }
                CalendarReader.hiddenCalendarIDs = hidden
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
        let byAccount = Dictionary(grouping: reader.calendars()) { $0.source?.title ?? "Other" }
        groups = byAccount.keys.sorted().map { account in
            AccountGroup(id: account, calendars: (byAccount[account] ?? []).map { calendar in
                CalendarRow(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    color: calendar.cgColor.map { Color(cgColor: $0) } ?? Theme.brand
                )
            })
        }
        today = Dictionary(grouping: reader.meetingsToday(includingHidden: true)) { $0.calendarID }
            .mapValues { events in events.map { $0.title.isEmpty ? "Untitled" : $0.title } }
        hidden = CalendarReader.hiddenCalendarIDs
    }
}
