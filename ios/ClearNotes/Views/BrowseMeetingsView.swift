import SwiftData
import SwiftUI
import UIKit

/// Meetings by day: a month calendar with a dot on each day that has a recording (tap the month
/// to jump to another month or year), and the chosen day's meetings below it.
struct MeetingsCalendarView: View {
    @Query(filter: #Predicate<Meeting> { $0.deletedAt == nil }, sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @State private var selectedDay: DateComponents?

    private var calendar: Calendar { .current }

    private var meetingDays: Set<DateComponents> {
        Set(meetings.map { MeetingCalendar.day(of: $0.createdAt, in: calendar) })
    }

    private var dayMeetings: [Meeting] {
        guard let selectedDay else { return [] }
        return meetings
            .filter { MeetingCalendar.day(of: $0.createdAt, in: calendar) == selectedDay }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var selectedDate: Date? {
        selectedDay.flatMap { calendar.date(from: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MeetingCalendar(meetingDays: meetingDays, selected: $selectedDay)
                    .frame(minHeight: 380)
                    .cardStyle(padding: 8)

                if let selectedDate {
                    Eyebrow(selectedDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    if dayMeetings.isEmpty {
                        Text("No meetings recorded on this day.")
                            .foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardStyle()
                    } else {
                        ForEach(dayMeetings) { meeting in
                            NavigationLink {
                                MeetingDetailView(meeting: meeting)
                            } label: {
                                MeetingCard(meeting: meeting)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .background { GlowBackground() }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Today, or the latest day with a meeting when there's none today.
            guard selectedDay == nil else { return }
            let today = MeetingCalendar.day(of: .now, in: calendar)
            if meetingDays.contains(today) || meetings.isEmpty {
                selectedDay = today
            } else {
                selectedDay = meetings.first.map { MeetingCalendar.day(of: $0.createdAt, in: calendar) }
            }
        }
    }
}

/// Apple's calendar (UICalendarView), with a dot on days that have meetings.
struct MeetingCalendar: UIViewRepresentable {
    var meetingDays: Set<DateComponents>
    @Binding var selected: DateComponents?

    /// A date as year, month and day only, so days compare equal.
    static func day(of date: Date, in calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    func makeUIView(context: Context) -> UICalendarView {
        let view = UICalendarView()
        view.calendar = Calendar.current
        view.locale = .current
        view.fontDesign = .rounded
        view.tintColor = UIColor(Theme.brand)
        view.delegate = context.coordinator
        let selection = UICalendarSelectionSingleDate(delegate: context.coordinator)
        selection.selectedDate = selected
        view.selectionBehavior = selection
        if let selected, let date = Calendar.current.date(from: selected) {
            view.visibleDateComponents = Calendar.current.dateComponents([.year, .month, .day], from: date)
        }
        context.coordinator.days = meetingDays
        return view
    }

    func updateUIView(_ view: UICalendarView, context: Context) {
        context.coordinator.parent = self
        let changed = context.coordinator.days.symmetricDifference(meetingDays)
        if !changed.isEmpty {
            context.coordinator.days = meetingDays
            view.reloadDecorations(forDateComponents: Array(changed), animated: true)
        }
        if let selection = view.selectionBehavior as? UICalendarSelectionSingleDate,
           normalized(selection.selectedDate) != selected {
            selection.setSelected(selected, animated: false)
            if let selected {
                view.setVisibleDateComponents(selected, animated: true)
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    private func normalized(_ components: DateComponents?) -> DateComponents? {
        components.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) }
    }

    final class Coordinator: NSObject, UICalendarViewDelegate, UICalendarSelectionSingleDateDelegate {
        var parent: MeetingCalendar
        var days: Set<DateComponents> = []

        init(parent: MeetingCalendar) {
            self.parent = parent
        }

        func calendarView(_ calendarView: UICalendarView, decorationFor dateComponents: DateComponents) -> UICalendarView.Decoration? {
            let day = DateComponents(year: dateComponents.year, month: dateComponents.month, day: dateComponents.day)
            return days.contains(day) ? .default(color: UIColor(Theme.brand), size: .medium) : nil
        }

        func dateSelection(_ selection: UICalendarSelectionSingleDate, didSelectDate dateComponents: DateComponents?) {
            parent.selected = dateComponents.map { DateComponents(year: $0.year, month: $0.month, day: $0.day) }
        }
    }
}

/// Every recorded meeting in a series (the same repeating calendar meeting, or the same title),
/// newest first.
struct SeriesListView: View {
    let meeting: Meeting
    @Query(filter: #Predicate<Meeting> { $0.deletedAt == nil }, sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]

    private var series: [Meeting] { MeetingSeries.all(like: meeting, in: meetings) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(series.count) meetings")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(series) { item in
                    if item === meeting {
                        VStack(alignment: .leading, spacing: 6) {
                            Eyebrow("This meeting")
                            MeetingCard(meeting: item)
                                .overlay(
                                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                                        .strokeBorder(Theme.brand, lineWidth: 1.5)
                                )
                        }
                    } else {
                        NavigationLink {
                            MeetingDetailView(meeting: item)
                        } label: {
                            MeetingCard(meeting: item)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 40)
        }
        .background { GlowBackground() }
        .navigationTitle(meeting.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
