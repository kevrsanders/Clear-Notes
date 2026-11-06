import SwiftUI

/// What the user chose to record on the Record sheet.
struct RecordChoice: Equatable {
    var kind: MeetingKind
    /// The diary meeting it's for, if any.
    var event: CalendarMeeting?
}

/// Shown when Record is tapped: the diary meeting on now, one tap away, or something that isn't in
/// the diary (a quick catch-up, a voice note or another meeting).
struct RecordChoiceSheet: View {
    /// The diary meeting on now or about to start, offered first.
    var current: CalendarMeeting?
    /// Today's other diary meetings, behind "Another meeting from today's diary".
    var others: [CalendarMeeting]
    var calendarOn: Bool
    var onChoose: (RecordChoice) -> Void

    @State private var showOthers = false

    private var hasDiary: Bool { current != nil || !others.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("What are you recording?")
                    .font(.title3.bold())
                    .padding(.top, 26)
                    .padding(.bottom, 6)

                if hasDiary {
                    Eyebrow("In your diary")
                    if let current {
                        diaryCard(current)
                    }
                    if !others.isEmpty {
                        Button {
                            withAnimation(.snappy) { showOthers.toggle() }
                        } label: {
                            HStack(spacing: 5) {
                                Text(current == nil ? "A meeting from today's diary" : "Another meeting from today's diary")
                                Image(systemName: showOthers ? "chevron.up" : "chevron.down")
                                    .font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.brand)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        if showOthers {
                            VStack(spacing: 0) {
                                ForEach(Array(others.enumerated()), id: \.element.id) { index, event in
                                    if index > 0 { Divider() }
                                    otherRow(event)
                                }
                            }
                            .cardStyle(padding: 14)
                        }
                    }
                    Eyebrow("Not in your diary")
                        .padding(.top, 10)
                }

                option(.catchUp, title: MeetingKind.catchUp.title)
                option(.voiceNote, title: MeetingKind.voiceNote.title)
                option(.meeting, title: hasDiary || calendarOn ? "Other meeting" : "Meeting")

                if !calendarOn {
                    Text("Turn on Use my calendar in Settings to record meetings from your diary here, with their title and who's invited.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 24)
        }
    }

    private func diaryCard(_ event: CalendarMeeting) -> some View {
        let people = event.attendees.enumerated().map { index, name in
            Speaker(id: "\(index)", number: index + 1, name: name)
        }
        let names = event.attendees
        let peopleLine = names.count > 2 ? names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)" : names.joined(separator: ", ")
        return Button {
            onChoose(RecordChoice(kind: .meeting, event: event))
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Theme.record)
                            .frame(width: 7, height: 7)
                        Eyebrow("\(event.start <= .now ? "Now" : "Starting") · \(event.timeRange)")
                    }
                    Text(event.title.isEmpty ? "Calendar event" : event.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !people.isEmpty {
                        HStack(spacing: 8) {
                            AvatarStack(speakers: people, size: 22, limit: 3)
                            Text(peopleLine)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Theme.recordGradient, in: Circle())
                    .shadow(color: Theme.record.opacity(0.35), radius: 10, y: 4)
            }
            .cardStyle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record \(event.title.isEmpty ? "the meeting on now" : event.title)")
    }

    private func otherRow(_ event: CalendarMeeting) -> some View {
        Button {
            onChoose(RecordChoice(kind: .meeting, event: event))
        } label: {
            HStack(spacing: 12) {
                Text(event.start.formatted(date: .omitted, time: .shortened))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(minWidth: 44, alignment: .leading)
                Text(event.title.isEmpty ? "Calendar event" : event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "mic.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.record)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Record \(event.title), \(event.timeRange)")
    }

    private func option(_ kind: MeetingKind, title: String) -> some View {
        Button {
            onChoose(RecordChoice(kind: kind, event: nil))
        } label: {
            HStack(alignment: .top, spacing: 12) {
                IconTile(systemName: kind.systemImage, tint: kind.tint, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(kind.recordHint)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 4)
            }
            .cardStyle(padding: 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
