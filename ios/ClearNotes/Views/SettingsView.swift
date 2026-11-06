import Speech
import SwiftData
import SwiftUI
import UIKit

enum SettingsKeys {
    static let showConsentReminder = "showConsentReminder"
    static let requireOnDevice = "requireOnDeviceTranscription"
    static let identifySpeakers = "identifySpeakers"
    static let speakerModelsReady = "speakerModelsReady"
    static let myName = "myName"
    static let audioRetention = "audioRetentionDays"
    static let reduceEchoAndNoise = "reduceEchoAndNoise"
    static let rememberVoices = "rememberVoices"
    static let useCalendar = "useCalendar"
    static let calendarChoices = "calendarChoices"
    static let actionSuggestions = "actionSuggestions"
    static let accurateTranscripts = "accurateTranscripts"
    static let accurateModelsReady = "accurateModelsReady"
    static let customVocabulary = "customVocabulary"
    static let continueInBackground = "continueInBackground"
    static let appearance = "appearance"
}

/// Light or dark: like the iPhone by default, or always one or the other.
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: "Match iPhone"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }

    /// Applies to every window, sheets included. (SwiftUI's preferredColorScheme doesn't always
    /// switch back to matching the iPhone until the app restarts.) The recording screen stays dark.
    @MainActor
    static func apply(_ rawValue: String) {
        let style = (AppAppearance(rawValue: rawValue) ?? .system).interfaceStyle
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

struct SettingsView: View {
    @AppStorage(SettingsKeys.showConsentReminder) private var showConsentReminder = true
    @AppStorage(SettingsKeys.requireOnDevice) private var requireOnDevice = true
    @AppStorage(SettingsKeys.identifySpeakers) private var identifySpeakers = true
    @AppStorage(SettingsKeys.speakerModelsReady) private var speakerModelsReady = false
    @AppStorage(SettingsKeys.myName) private var myName = ""
    @AppStorage(SettingsKeys.audioRetention) private var audioRetention = AudioRetention.default.rawValue
    @AppStorage(SettingsKeys.reduceEchoAndNoise) private var reduceEchoAndNoise = false
    @AppStorage(SettingsKeys.rememberVoices) private var rememberVoices = false
    @AppStorage(SettingsKeys.useCalendar) private var useCalendar = false
    @AppStorage(SettingsKeys.actionSuggestions) private var actionSuggestions = ActionSuggestions.default.rawValue
    @AppStorage(SettingsKeys.accurateTranscripts) private var accurateTranscripts = false
    @AppStorage(SettingsKeys.accurateModelsReady) private var accurateModelsReady = false
    @AppStorage(SettingsKeys.customVocabulary) private var customVocabulary = ""
    @AppStorage(SettingsKeys.continueInBackground) private var continueInBackground = true
    @AppStorage(SettingsKeys.appearance) private var appearance = AppAppearance.system.rawValue
    @State private var isDownloadingTranscriber = false
    @State private var transcriberError: String?
    @State private var calendarBlocked = CalendarReader.isBlocked
    @Query private var voices: [VoiceProfile]
    @State private var isDownloading = false
    @State private var downloadError: String?

    private var onDeviceSpeechSupported: Bool {
        SFSpeechRecognizer()?.supportsOnDeviceRecognition ?? false
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Settings")
                        .font(.system(size: 34, weight: .bold))
                        .tracking(-0.6)
                        .padding(.top, 12)

                    hero

                    section("You") {
                        HStack {
                            Text("Your name")
                            Spacer()
                            TextField("Used for “Me”", text: $myName)
                                .multilineTextAlignment(.trailing)
                                .textContentType(.name)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    section("Appearance", footer: "Match iPhone follows Light or Dark in iPhone Settings → Display & Brightness. The recording screen is always dark.") {
                        Picker("Appearance", selection: $appearance) {
                            ForEach(AppAppearance.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    section("Privacy", footer: "When on-device transcription is required, speech never leaves this iPhone. Turning it off lets Apple's servers transcribe languages this iPhone can't handle itself.") {
                        toggle("Transcribe on this iPhone only", systemImage: "lock.iphone", isOn: $requireOnDevice)
                        Divider()
                        toggle("Remind me to tell attendees", systemImage: "person.wave.2", isOn: $showConsentReminder)
                    }

                    section("Transcription", footer: "More accurate transcripts: after each meeting, the recording is transcribed again on this iPhone with NVIDIA's Parakeet model, which is more accurate than the live transcript, and the live one is replaced. It's a one-off download of about 450 MB; turning it off deletes it. My words: names and terms to spell correctly, such as colleagues' names and acronyms. People invited to the meeting are included automatically.") {
                        Toggle(isOn: accurateToggle) {
                            Label {
                                Text("More accurate transcripts")
                            } icon: {
                                Image(systemName: "text.badge.checkmark")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        .tint(Theme.brand)
                        .disabled(!AccurateTranscriber.isSupported || isDownloadingTranscriber)
                        if accurateTranscripts || isDownloadingTranscriber || transcriberError != nil {
                            HStack(spacing: 10) {
                                if isDownloadingTranscriber {
                                    ProgressView()
                                }
                                Text(transcriberStatus)
                                    .font(.footnote)
                                    .foregroundStyle(transcriberError == nil ? Theme.textSecondary : Theme.warning)
                            }
                        }
                        Divider()
                        NavigationLink {
                            VocabularyView()
                        } label: {
                            HStack {
                                Label {
                                    Text("My words")
                                } icon: {
                                    Image(systemName: "character.book.closed")
                                        .foregroundStyle(Theme.brand)
                                }
                                Spacer()
                                Text("\(Vocabulary.terms(from: customVocabulary).count)")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    if #available(iOS 26.0, *) {
                        section("After recording", footer: "If you leave Clear Notes while the transcript is improved and speakers are identified, iOS can let that carry on, with its progress in the Dynamic Island and on the Lock Screen. Notes and minutes are written with Clear Notes open, and carry on from where they stopped when you come back.") {
                            toggle("Keep going when I leave the app", systemImage: "hourglass", isOn: $continueInBackground)
                        }
                    }

                    section("Actions", footer: (ActionSuggestions(rawValue: actionSuggestions) ?? .default).explanation + " While recording, tap Mark action or Mark decision just after one is agreed, or say \"action point\" or \"decision point\". Marked moments become open actions and decisions after the meeting.") {
                        Picker(selection: $actionSuggestions) {
                            ForEach(ActionSuggestions.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        } label: {
                            Label {
                                Text("Suggest actions")
                            } icon: {
                                Image(systemName: "checklist")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        .tint(Theme.brand)
                    }

                    section("Calendar", footer: "Reads today's events from your main calendar, and from any others you turn on in Choose calendars. Colleagues' shared calendars stay off unless you turn them on. Meetings with other people invited come before blocks like WFH or Focus time. Recordings take the meeting's title, invited people are suggested when naming speakers and action owners, and the Teams link is kept for later. Only the title, invited names and Teams link are saved with each meeting. Nothing is sent anywhere.") {
                        Toggle(isOn: calendarToggle) {
                            Label {
                                Text("Use my calendar")
                            } icon: {
                                Image(systemName: "calendar")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        .tint(Theme.brand)
                        if useCalendar && CalendarReader.hasAccess {
                            Divider()
                            NavigationLink {
                                CalendarsView()
                            } label: {
                                Text("Choose calendars")
                            }
                        }
                        if calendarBlocked {
                            Divider()
                            HStack(spacing: 12) {
                                Text("Calendar access is off for Clear Notes. Turn on Full Access in iOS Settings.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.warning)
                                Spacer(minLength: 0)
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    Button("Settings") { UIApplication.shared.open(url) }
                                        .buttonStyle(SecondaryButtonStyle(compact: true))
                                }
                            }
                        }
                    }

                    section("Microphone", footer: "Echo and noise reduction is the processing iPhone uses for speakerphone calls. It cleans up echo and hiss but works best within a metre or two, so it can quieten people further away. Leave it off for meetings round a table. A plugged-in USB conference microphone is used automatically and picks up a room best.") {
                        toggle("Reduce echo and noise", systemImage: "waveform.badge.minus", isOn: $reduceEchoAndNoise)
                    }

                    section("Recordings", footer: (AudioRetention(rawValue: audioRetention) ?? .default).promise + " Recordings are excluded from backups and never leave this iPhone.") {
                        Picker(selection: $audioRetention) {
                            ForEach(AudioRetention.allCases) { option in
                                Text(option.title).tag(option.rawValue)
                            }
                        } label: {
                            Label {
                                Text("Keep recordings")
                            } icon: {
                                Image(systemName: "waveform")
                                    .foregroundStyle(Theme.brand)
                            }
                        }
                        .tint(Theme.brand)
                    }

                    section("Speakers", footer: "Voices are separated on this iPhone after each meeting. The speaker models are downloaded once. No meeting data is sent. Remember voices (off by default) saves a voiceprint when you name someone, only with their agreement, so later meetings can suggest their name. Voiceprints are biometric data: check with your Information Governance team before using this with colleagues.") {
                        toggle("Identify speakers", systemImage: "person.2.wave.2", isOn: $identifySpeakers)
                            .disabled(!SpeakerSeparators.isSupported)
                        Divider()
                        modelsRow
                        Divider()
                        toggle("Remember voices", systemImage: "person.wave.2.fill", isOn: $rememberVoices)
                            .disabled(!SpeakerSeparators.isSupported)
                        if rememberVoices || !voices.isEmpty {
                            NavigationLink {
                                VoicesView()
                            } label: {
                                HStack {
                                    Text("Remembered voices")
                                    Spacer()
                                    Text("\(voices.count)")
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }

                    section("This iPhone") {
                        status(
                            "On-device transcription",
                            ok: onDeviceSpeechSupported,
                            detail: Locale.current.localizedString(forIdentifier: Locale.current.identifier) ?? Locale.current.identifier
                        )
                        Divider()
                        status(
                            "Apple Intelligence notes",
                            ok: NotesEnhancers.isAppleIntelligenceAvailable,
                            detail: NotesEnhancers.isAppleIntelligenceAvailable
                                ? "Summaries and actions are written on this iPhone"
                                : "Not available, so basic extraction is used"
                        )
                    }

                    section("About") {
                        LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")
                        Divider()
                        Text("Phase 1: on-device capture, speakers, notes and calendar. Microsoft 365 and Teams integrations and cross-meeting search come in Phase 2.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.immediately)
            .background { GlowBackground() }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                calendarBlocked = CalendarReader.isBlocked
                // Access may have been removed in iOS Settings since it was turned on.
                if useCalendar && !CalendarReader.hasAccess && CalendarReader.hasAnswered {
                    useCalendar = false
                }
            }
        }
    }

    private var transcriberStatus: String {
        if let transcriberError { return transcriberError }
        if isDownloadingTranscriber { return "Downloading about 450 MB. Keep Clear Notes open; Wi-Fi recommended." }
        return accurateModelsReady ? "Ready on this iPhone" : "Not downloaded yet"
    }

    /// Turning it on downloads the model; turning it off deletes it to free the space.
    private var accurateToggle: Binding<Bool> {
        Binding {
            accurateTranscripts
        } set: { isOn in
            transcriberError = nil
            accurateTranscripts = isOn
            Task { @MainActor in
                if isOn {
                    isDownloadingTranscriber = true
                    do {
                        try await AccurateTranscriber.shared.prepare()
                        accurateModelsReady = true
                    } catch {
                        accurateTranscripts = false
                        transcriberError = "Download failed. Check your connection and try again."
                    }
                    isDownloadingTranscriber = false
                } else {
                    await AccurateTranscriber.shared.removeModels()
                    accurateModelsReady = false
                }
            }
        }
    }

    /// Turning the calendar on asks iOS for access first, and stays off if it isn't given.
    private var calendarToggle: Binding<Bool> {
        Binding {
            useCalendar
        } set: { isOn in
            guard isOn else {
                useCalendar = false
                return
            }
            Task { @MainActor in
                let granted = await CalendarReader.shared.requestAccess()
                useCalendar = granted
                calendarBlocked = !granted
            }
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            IconTile(systemName: "waveform", tint: nil, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                Text("Clear Notes")
                    .font(.headline)
                Text("Private by design. Audio, transcripts and notes stay on this iPhone.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .cardStyle()
    }

    @ViewBuilder
    private var modelsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundStyle(Theme.brand)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("Speaker models")
                Text(modelStatus)
                    .font(.footnote)
                    .foregroundStyle(downloadError == nil ? Theme.textSecondary : Theme.warning)
            }
            Spacer()
            if isDownloading {
                ProgressView()
            } else if SpeakerSeparators.isSupported && !speakerModelsReady {
                Button("Download") { Task { await downloadModels() } }
                    .buttonStyle(PrimaryButtonStyle(compact: true))
            } else if speakerModelsReady {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.success)
            }
        }
    }

    private var modelStatus: String {
        if let downloadError { return downloadError }
        if !SpeakerSeparators.isSupported { return "Not included in this build" }
        if isDownloading { return "Downloading…" }
        return speakerModelsReady ? "Ready on this iPhone" : "Downloaded automatically after your first meeting"
    }

    private func downloadModels() async {
        isDownloading = true
        downloadError = nil
        do {
            try await SpeakerSeparators.prepareModels()
            speakerModelsReady = true
        } catch {
            downloadError = "Download failed. Check your connection and try again."
        }
        isDownloading = false
    }

    // MARK: - Building blocks

    private func section<Content: View>(_ title: String, footer: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(title)
                .padding(.horizontal, 4)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .cardStyle(padding: 16)
            if let footer {
                Text(footer)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func toggle(_ title: String, systemImage: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.brand)
            }
        }
        .tint(Theme.brand)
    }

    private func status(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle.fill")
                .foregroundStyle(ok ? Theme.success : Theme.warning)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}
