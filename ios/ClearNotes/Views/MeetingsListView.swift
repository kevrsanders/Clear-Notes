import SwiftData
import SwiftUI

/// Home: greeting, today's diary, quick stats, and meetings grouped by day, which can be filtered by
/// type. Record (in the tab bar) asks what's being recorded.
struct MeetingsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Meeting.createdAt, order: .reverse) private var meetings: [Meeting]
    @AppStorage(SettingsKeys.showConsentReminder) private var showConsentReminder = true
    @AppStorage(SettingsKeys.identifySpeakers) private var identifySpeakers = true
    @AppStorage(SettingsKeys.myName) private var myName = ""
    @AppStorage(SettingsKeys.useCalendar) private var useCalendar = false
    @Environment(\.scenePhase) private var scenePhase

    @State private var path: [Meeting] = []
    @State private var showCalendar = false
    @State private var search = ""
    @State private var showConsent = false
    @State private var startAfterConsent = false
    @State private var showRecorder = false
    @State private var finishedMeeting: Meeting?
    /// Today's calendar events, when Use my calendar is on.
    @State private var todaysEvents: [CalendarMeeting] = []
    /// The diary event being recorded, if any.
    @State private var recordingEvent: CalendarMeeting?
    /// What's being recorded: a meeting, a quick catch-up or a voice note.
    @State private var recordingKind: MeetingKind = .meeting
    /// The Record sheet ("What are you recording?"), and what was chosen on it.
    @State private var choosingRecording = false
    @State private var pendingChoice: RecordChoice?
    @State private var filter: MeetingFilter = .all
    /// The previous meeting in the Up next meeting's series, shown in a sheet.
    @State private var lastTimeMeeting: Meeting?
    /// Opened after the Last time sheet closes, when the user asks for the full meeting.
    @State private var openAfterSheet: Meeting?

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if search.isEmpty, !diaryEntries.isEmpty {
                        DiaryTodayCard(
                            entries: diaryEntries,
                            lastTime: diaryLastTime,
                            onRecord: { newMeeting(for: $0, kind: .meeting) },
                            onOpen: { path.append($0) },
                            onShowLastTime: { lastTimeMeeting = $0 }
                        )
                    }
                    SearchField(text: $search)
                    if meetings.isEmpty {
                        emptyState
                    } else if search.isEmpty {
                        stats
                        filterBar
                        if sections.isEmpty {
                            Text("Nothing here yet. Tap Record and choose \(filter == .voiceNotes ? "Voice note" : filter == .catchUps ? "Quick catch-up" : "a diary meeting").")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .cardStyle()
                        }
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
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background { GlowBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Meeting.self) { MeetingDetailView(meeting: $0) }
            .navigationDestination(isPresented: $showCalendar) { MeetingsCalendarView() }
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
            // Record lives in the tab bar (see ContentView), which posts this.
            .onReceive(NotificationCenter.default.publisher(for: .startRecording)) { _ in
                path = []
                refreshCalendar()
                choosingRecording = true
            }
            .sheet(isPresented: $choosingRecording, onDismiss: {
                guard let choice = pendingChoice else { return }
                pendingChoice = nil
                newMeeting(for: choice.event, kind: choice.kind)
            }) {
                RecordChoiceSheet(current: recordNow, others: recordOthers, calendarOn: useCalendar) { choice in
                    pendingChoice = choice
                    choosingRecording = false
                }
                .presentationDetents(recordNow != nil || !recordOthers.isEmpty ? [PresentationDetent.large] : [PresentationDetent.fraction(0.66), .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(32)
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
            RecordingView(calendarMeeting: recordingEvent, kind: recordingKind, onFinish: saveMeeting)
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
                GlassCircleButton(systemName: "calendar", accessibilityLabel: "Meetings by day") {
                    showCalendar = true
                }
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

    /// All · Diary · Catch-ups · Voice notes.
    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MeetingFilter.allCases) { option in
                    Button {
                        withAnimation(.snappy) { filter = option }
                    } label: {
                        Text(option.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(filter == option ? Color.primary : Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .frame(height: 34)
                            .background {
                                Capsule().fill(filter == option ? Theme.surfaceRaised : Color.primary.opacity(0.05))
                            }
                            .overlay(Capsule().strokeBorder(Theme.stroke))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
        }
        .scrollClipDisabled()
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

    /// Today, this week, then one section per month ("October 2026"), so older meetings aren't
    /// one long list. The calendar button finds a particular day.
    private var sections: [MeetingSection] {
        let calendar = Calendar.current
        let weekStart = calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: .now)) ?? .now
        let shown = meetings.filter { filter.matches($0) }
        let today = shown.filter { calendar.isDateInToday($0.createdAt) }
        let week = shown.filter { !calendar.isDateInToday($0.createdAt) && $0.createdAt >= weekStart }
        var result = [
            MeetingSection(title: "Today", meetings: today),
            MeetingSection(title: "This week", meetings: week),
        ]
        // Meetings are newest first, so months come out newest first too.
        for meeting in shown where meeting.createdAt < weekStart {
            let month = meeting.createdAt.formatted(.dateTime.month(.wide).year())
            if result.last?.title == month {
                result[result.count - 1].meetings.append(meeting)
            } else {
                result.append(MeetingSection(title: month, meetings: [meeting]))
            }
        }
        return result.filter { !$0.meetings.isEmpty }
    }

    // MARK: - Calendar

    /// The meeting happening now, or else the next one today. Meetings with people come before
    /// blocks such as "WFH" or "Focus time".
    private var upNext: (event: CalendarMeeting, isNow: Bool)? {
        CalendarMeetingPicker.upNext(in: todaysEvents, at: .now)
    }

    /// Today's diary: what was recorded, what's on now and what's later.
    private var diaryEntries: [DiaryEntry] {
        DiaryDay.entries(events: todaysEvents, meetings: meetings, now: .now)
    }

    /// "Last time" for the meeting on now or next, when an earlier one in its series was recorded.
    private var diaryLastTime: Meeting? {
        guard let upNext else { return nil }
        let isListed = diaryEntries.contains { $0.event.id == upNext.event.id && $0.status != .recorded }
        return isListed ? previousMeeting(for: upNext.event) : nil
    }

    /// The diary meeting on now or about to start, offered first on the Record sheet.
    private var recordNow: CalendarMeeting? {
        guard useCalendar else { return nil }
        return CalendarMeetingPicker.current(in: todaysEvents, at: .now)
    }

    /// Today's other diary meetings with people, from a couple of hours ago (one that overran) on.
    private var recordOthers: [CalendarMeeting] {
        guard useCalendar else { return [] }
        let now = Date.now
        return todaysEvents.filter { event in
            CalendarMeetingPicker.usable(event) && event.hasPeople && event.id != recordNow?.id
                && event.end > now.addingTimeInterval(-2 * 3_600)
        }
    }

    /// The last meeting in the same series as a calendar event, if one was recorded.
    private func previousMeeting(for event: CalendarMeeting) -> Meeting? {
        MeetingSeries.previous(seriesID: event.seriesID, title: event.title, before: event.start, in: meetings)
    }

    private func refreshCalendar() {
        todaysEvents = useCalendar ? CalendarReader.shared.meetingsToday() : []
    }

    // MARK: - Recording

    private func newMeeting(for event: CalendarMeeting?, kind: MeetingKind) {
        recordingEvent = event
        recordingKind = kind
        // Nobody else is recorded in a voice note, so there's no one to tell.
        if showConsentReminder && kind != .voiceNote {
            showConsent = true
        } else {
            showRecorder = true
        }
    }

    private func saveMeeting(_ result: RecordingResult, notes: String, event: CalendarMeeting?) {
        let start = Date().addingTimeInterval(-result.duration)
        // A voice note is just the user, so there are no voices to tell apart.
        let separatesSpeakers = identifySpeakers && SpeakerSeparators.isSupported && result.kind != .voiceNote
        let meeting = Meeting(
            title: Meeting.defaultTitle(for: start, kind: result.kind),
            createdAt: start,
            duration: result.duration,
            userNotes: notes,
            segments: result.segments,
            pendingAudioFileName: separatesSpeakers ? result.audioFileName : nil
        )
        meeting.marks = result.marks
        meeting.expectedSpeakers = result.kind == .voiceNote ? nil : result.expectedSpeakers
        meeting.kind = result.kind
        if let event {
            meeting.link(to: event)
        } else if result.kind == .catchUp {
            meeting.setCatchUpPerson(result.person)
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

/// Today's diary at a glance: each meeting with whether it was recorded, is on now (one tap to
/// record), is later, or went by without a recording.
private struct DiaryTodayCard: View {
    let entries: [DiaryEntry]
    /// The previous meeting in the series of the meeting on now or next, for "Last time".
    var lastTime: Meeting?
    var onRecord: (CalendarMeeting) -> Void
    var onOpen: (Meeting) -> Void
    var onShowLastTime: (Meeting) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Today in your diary")
                .padding(.bottom, 6)
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 { Divider() }
                row(entry)
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
                    .padding(.top, 10)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the summary and actions from the last meeting in this series")
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private func row(_ entry: DiaryEntry) -> some View {
        let content = HStack(spacing: 12) {
            Text(entry.event.start.formatted(date: .omitted, time: .shortened))
                .font(.footnote.monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 44, alignment: .leading)
            Text(entry.event.title.isEmpty ? "Calendar event" : entry.event.title)
                .font(.subheadline.weight(entry.status == .notRecorded ? .regular : .semibold))
                .foregroundStyle(entry.status == .notRecorded ? Theme.textSecondary : Color.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            status(entry.status)
        }
        .padding(.vertical, 9)
        .contentShape(Rectangle())

        switch entry.status {
        case .recorded:
            if let meeting = entry.meeting {
                Button { onOpen(meeting) } label: { content }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the recording")
            } else {
                content
            }
        case .now:
            Button { onRecord(entry.event) } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("Record \(entry.event.title), \(entry.event.timeRange)")
        case .later, .notRecorded:
            content
        }
    }

    @ViewBuilder
    private func status(_ status: DiaryStatus) -> some View {
        switch status {
        case .recorded:
            Chip(text: "Recorded", systemImage: "checkmark", tint: Theme.success)
        case .now:
            HStack(spacing: 5) {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("Record")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.recordGradient, in: Capsule())
        case .later:
            Chip(text: "Later")
        case .notRecorded:
            Text("Not recorded")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .overlay(Capsule().strokeBorder(Theme.textTertiary, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
        }
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
            HStack(spacing: 8) {
                KindBadge(meeting: meeting, size: 22)
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
                            text: "\(meeting.openActionCount) \(meeting.kind == .voiceNote ? "to-do" : "action")\(meeting.openActionCount == 1 ? "" : "s")",
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
