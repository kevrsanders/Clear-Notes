import SwiftData
import SwiftUI

/// Home: greeting, quick stats, meetings grouped by day and the floating Record button.
struct MeetingsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @AppStorage(SettingsKeys.showConsentReminder) private var showConsentReminder = true
    @AppStorage(SettingsKeys.identifySpeakers) private var identifySpeakers = true
    @AppStorage(SettingsKeys.myName) private var myName = ""
    @AppStorage(SettingsKeys.useCalendar) private var useCalendar = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [Meeting] = []
    @State private var search = ""
    @State private var showConsent = false
    @State private var startAfterConsent = false
    @State private var showRecorder = false
    @State private var finishedMeeting: Meeting?
    /// Today's calendar events, when Use my calendar is on.
    @State private var todaysEvents: [CalendarMeeting] = []
    /// The event the user tapped Record on. Nil lets the recorder find the meeting happening now.
    @State private var recordingEvent: CalendarMeeting?
    /// The previous meeting in the Up next meeting's series, shown in a sheet.
    @State private var lastTimeMeeting: Meeting?
    /// Opened after the Last time sheet closes, when the user asks for the full meeting.
    @State private var openAfterSheet: Meeting?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if search.isEmpty, let upNext {
                        UpNextCard(
                            event: upNext.event,
                            isNow: upNext.isNow,
                            lastTime: previousMeeting(for: upNext.event),
                            onShowLastTime: { lastTimeMeeting = $0 },
                            onRecord: { newMeeting(for: upNext.event) }
                        )
                    }
                    SearchField(text: $search)
                    if meetings.isEmpty {
                        emptyState
                    } else if search.isEmpty {
                        stats
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                Eyebrow(section.title)
                                ForEach(section.meetings) { card(for: $0) }
                            }
                        }
                    } else if searchResults.isEmpty {
                        ContentUnavailableView.search(text: search)
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Eyebrow("\(searchResults.count) result\(searchResults.count == 1 ? "" : "s")")
                            ForEach(searchResults) { card(for: $0) }
                        }
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.immediately)
            .background { GlowBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Meeting.self) { MeetingDetailView(meeting: $0) }
            // A meeting just imported from a shared file.
            .onReceive(NotificationCenter.default.publisher(for: .openMeeting)) { note in
                guard let id = note.object as? PersistentIdentifier,
                      let meeting = meetings.first(where: { $0.persistentModelID == id })
                else { return }
                path = [meeting]
            }
            .sheet(item: $lastTimeMeeting, onDismiss: {
                if let meeting = openAfterSheet {
                    openAfterSheet = nil
                    path.append(meeting)
                }
            }) { previous in
                LastTimeView(meeting: previous) {
                    openAfterSheet = previous
                    lastTimeMeeting = nil
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
            }
            .overlay(alignment: .bottom) {
                RecordButton { newMeeting(for: nil) }
                    .padding(.bottom, 12)
            }
        }
        .task(id: useCalendar) {
            // Keeps "Now" and "Next" current while the home screen is open.
            while !Task.isCancelled {
                refreshCalendar()
                try? await Task.sleep(for: .seconds(60))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshCalendar() }
        }
        .sheet(isPresented: $showConsent, onDismiss: {
            if startAfterConsent {
                startAfterConsent = false
                showRecorder = true
            }
        }) {
            ConsentSheet {
                startAfterConsent = true
                showConsent = false
            }
            .presentationDetents([.medium, .large])
            .presentationCornerRadius(32)
        }
        .fullScreenCover(isPresented: $showRecorder, onDismiss: openFinishedMeeting) {
            RecordingView(calendarMeeting: recordingEvent, onFinish: saveMeeting)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Eyebrow(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            HStack(alignment: .center) {
                Text(greeting)
                    .font(.system(size: 34, weight: .bold))
                    .tracking(-0.6)
                Spacer()
                if myName.isEmpty {
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Theme.brandGradient, in: Circle())
                        .accessibilityHidden(true)
                } else {
                    Avatar(name: myName, color: Theme.brand, size: 40)
                }
            }
        }
        .padding(.top, 12)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    /// Meeting counts only. Actions belong to their meeting, so they're shown on each meeting card.
    private var stats: some View {
        let calendar = Calendar.current
        let today = meetings.filter { calendar.isDateInToday($0.createdAt) }
        let weekStart = calendar.date(byAdding: .day, value: -7, to: .now) ?? .now
        let thisWeek = meetings.filter { $0.createdAt >= weekStart }
        func time(_ list: [Meeting]) -> String { list.reduce(TimeInterval(0)) { $0 + $1.duration }.compactDurationString }
        return HStack(spacing: 10) {
            StatTile(title: "Today", value: "\(today.count)", hint: "\(time(today)) recorded", tint: Theme.brand)
            StatTile(title: "This week", value: "\(thisWeek.count)", hint: "\(time(thisWeek)) of meetings", tint: .primary)
            StatTile(title: "All", value: "\(meetings.count)", hint: "\(time(meetings)) in total", tint: .primary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            IconTile(systemName: "waveform", tint: nil, size: 64)
            Text("Your meetings, minus the note-taking")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
            Text("Tap Record and put your iPhone on the table. Clear Notes transcribes on this iPhone, works out who said what, and turns it into a summary and actions. Nothing leaves your iPhone.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 24)
        .padding(.top, 8)
    }

    private func card(for meeting: Meeting) -> some View {
        NavigationLink(value: meeting) {
            MeetingCard(meeting: meeting)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                meeting.deleteAllAudio()
                context.delete(meeting)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Data

    private var searchResults: [Meeting] {
        meetings.filter { meeting in
            meeting.title.localizedCaseInsensitiveContains(search)
                || meeting.summary.localizedCaseInsensitiveContains(search)
                || meeting.userNotes.localizedCaseInsensitiveContains(search)
                || meeting.transcriptText.localizedCaseInsensitiveContains(search)
                || meeting.speakers.contains { $0.name?.localizedCaseInsensitiveContains(search) == true }
                || meeting.actions.contains { $0.text.localizedCaseInsensitiveContains(search) }
        }
    }

    private struct MeetingSection: Identifiable {
        var title: String
        var meetings: [Meeting]
        var id: String { title }
    }

    private var sections: [MeetingSection] {
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) ?? .now
        let today = meetings.filter { calendar.isDateInToday($0.createdAt) }
        let week = meetings.filter { !calendar.isDateInToday($0.createdAt) && $0.createdAt >= weekStart }
        let earlier = meetings.filter { $0.createdAt < weekStart }
        return [
            MeetingSection(title: "Today", meetings: today),
            MeetingSection(title: "This week", meetings: week),
            MeetingSection(title: "Earlier", meetings: earlier),
        ].filter { !$0.meetings.isEmpty }
    }

    // MARK: - Calendar

    /// The meeting happening now, or else the next one today. Meetings with people come before
    /// blocks such as "WFH" or "Focus time".
    private var upNext: (event: CalendarMeeting, isNow: Bool)? {
        CalendarMeetingPicker.upNext(in: todaysEvents, at: .now)
    }

    /// The last meeting in the same series as a calendar event, if one was recorded.
    private func previousMeeting(for event: CalendarMeeting) -> Meeting? {
        MeetingSeries.previous(seriesID: event.seriesID, title: event.title, before: event.start, in: meetings)
    }

    private func refreshCalendar() {
        todaysEvents = useCalendar ? CalendarReader.shared.meetingsToday() : []
    }

    // MARK: - Recording

    private func newMeeting(for event: CalendarMeeting?) {
        recordingEvent = event
        if showConsentReminder {
            showConsent = true
        } else {
            showRecorder = true
        }
    }

    private func saveMeeting(_ result: RecordingResult, notes: String, event: CalendarMeeting?) {
        let start = Date().addingTimeInterval(-result.duration)
        let separatesSpeakers = identifySpeakers && SpeakerSeparators.isSupported
        let meeting = Meeting(
            title: Meeting.defaultTitle(for: start),
            createdAt: start,
            duration: result.duration,
            userNotes: notes,
            segments: result.segments,
            pendingAudioFileName: separatesSpeakers ? result.audioFileName : nil
        )
        meeting.marks = result.marks
        meeting.expectedSpeakers = result.expectedSpeakers
        if let event {
            meeting.link(to: event)
        }
        if !separatesSpeakers {
            meeting.keepAudio(result.audioFileName)
        }
        context.insert(meeting)
        finishedMeeting = meeting
        Task { await MeetingProcessor.process(meeting) }
    }

    private func openFinishedMeeting() {
        guard let meeting = finishedMeeting else { return }
        finishedMeeting = nil
        path.append(meeting)
    }
}

/// The meeting happening now, or next today, with one tap to record it.
private struct UpNextCard: View {
    let event: CalendarMeeting
    let isNow: Bool
    /// The previous meeting in this series, if one was recorded.
    var lastTime: Meeting?
    var onShowLastTime: (Meeting) -> Void
    var onRecord: () -> Void

    private var people: [Speaker] {
        event.attendees.enumerated().map { index, name in
            Speaker(id: "\(index)", number: index + 1, name: name)
        }
    }

    private var peopleLine: String {
        let names = event.attendees
        guard names.count > 2 else { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)"
    }

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if isNow {
                        Circle()
                            .fill(Theme.record)
                            .frame(width: 7, height: 7)
                    }
                    Eyebrow("\(isNow ? "Now" : "Next") · \(event.timeRange)")
                }
                Text(event.title.isEmpty ? "Calendar event" : event.title)
                    .font(.headline)
                    .lineLimit(2)
                if !people.isEmpty || event.teamsJoinURL != nil || event.calendarName != nil {
                    HStack(spacing: 8) {
                        if !people.isEmpty {
                            AvatarStack(speakers: people, size: 22, limit: 3)
                            Text(peopleLine)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                        if event.teamsJoinURL != nil {
                            Chip(text: "Teams", systemImage: "video.fill", tint: Theme.brand)
                        }
                        if let calendarName = event.calendarName {
                            // Shown when it isn't the main calendar, so it's clear where an event comes from.
                            Chip(text: calendarName, systemImage: "calendar")
                        }
                    }
                }
                if let lastTime {
                    Button {
                        onShowLastTime(lastTime)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text(LastTime.summaryLine(lastTime))
                                .lineLimit(1)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.bold))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.brand)
                        .padding(.top, 2)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows the summary and actions from the last meeting in this series")
                }
            }
            Spacer(minLength: 0)
            Button(action: onRecord) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background(Theme.recordGradient, in: Circle())
                    .shadow(color: Theme.record.opacity(0.35), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Record \(event.title.isEmpty ? "this meeting" : event.title)")
        }
        .cardStyle()
    }
}

/// Glass search capsule.
private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textSecondary)
            TextField("Search meetings, people, actions", text: $text)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .glass(in: Capsule())
    }
}

struct MeetingCard: View {
    let meeting: Meeting

    private var timeText: String {
        let time = Calendar.current.isDateInToday(meeting.createdAt)
            ? meeting.createdAt.formatted(date: .omitted, time: .shortened)
            : meeting.createdAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())
        return "\(time) · \(meeting.duration.durationString)"
    }

    private var summaryPreview: String {
        meeting.summary
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "-• ")) }
            .joined(separator: " ")
    }

    /// "Processing", or "Notes 12/38" while a long meeting's notes are written.
    private var processingText: String {
        guard meeting.processingStage == .notes, meeting.notesPartsTotal > 1 else { return "Processing" }
        return "Notes \(min(meeting.notesPartsDone + 1, meeting.notesPartsTotal))/\(meeting.notesPartsTotal)"
    }

    private var speakerLine: String {
        let names = meeting.speakers.map(\.displayName)
        guard names.count > 2 else { return names.joined(separator: ", ") }
        return names.prefix(2).joined(separator: ", ") + " +\(names.count - 2)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(timeText)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                status
            }
            Text(meeting.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if !summaryPreview.isEmpty {
                Text(summaryPreview)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            if !meeting.speakers.isEmpty || meeting.openActionCount > 0 {
                HStack(spacing: 8) {
                    if !meeting.speakers.isEmpty {
                        AvatarStack(speakers: meeting.speakers)
                        Text(speakerLine)
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if meeting.openActionCount > 0 {
                        Chip(
                            text: "\(meeting.openActionCount) action\(meeting.openActionCount == 1 ? "" : "s")",
                            systemImage: "checklist",
                            tint: Theme.brand
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var status: some View {
        switch meeting.processingState {
        case .processing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text(processingText)
                    .monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.brand)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .accessibilityLabel("Notes couldn't be generated")
        case .ready:
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .accessibilityLabel("Processed on this iPhone")
        }
    }
}
