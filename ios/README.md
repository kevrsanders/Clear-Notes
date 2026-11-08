# Clear Notes for iPhone (Phase 1)

A native SwiftUI app that transcribes meetings on the iPhone, works out who said what, and turns it into a summary, decisions and actions. There is no meeting bot and no meeting data goes to a server. Recordings stay on the iPhone for playback and are deleted automatically after the period chosen in Settings (7 days by default, or as soon as notes are ready).

Design: see [docs/design-system.md](../docs/design-system.md) and the mockups in [docs/mockups/v2](../docs/mockups/v2) (light and dark).

## Features

- **Live capture**: big timer, level meter and a live transcript. Pause and resume. Recording continues when the screen locks, and pauses automatically for phone calls.
- **On-device transcription**: on iOS 26 it uses Apple's SpeechAnalyzer/SpeechTranscriber, a long-form model built for meetings and people further from the phone. On earlier versions it uses the older speech recogniser with `requiresOnDeviceRecognition`; a setting (on by default) refuses to record if your language can't be transcribed on the device.
- **More accurate transcripts** (Settings → Transcription, off by default): after each meeting, the kept recording is transcribed again on the iPhone with NVIDIA's Parakeet model (through FluidAudio: the English-only model for English, the multilingual one otherwise) and replaces the live transcript. It's a one-off download of about 450 MB, and turning it off deletes it. Older meetings with a kept recording have **Improve transcript** in the ⋯ menu; speaker names are kept, and actions keep their links. If the second pass fails or loses most of the words, the live transcript is kept.
- **My words** (Settings → Transcription): names and terms to spell correctly. Invited people, named speakers and your own name are added automatically. Corrections are cautious: the same letters ignoring case and spaces ("in tune" → "Intune"), except short dictionary words (so "it" never becomes "IT"), or a near miss on a word that isn't in the dictionary ("Jayson" → "Jason").
- **Edit a line**: hold a transcript line → *Edit text*.
- **Distant voices**: the transcriber gets a gentle automatic boost (up to about +12 dB, only while someone is speaking, with a limiter near full scale). The kept recording is the untouched microphone audio. The app uses a plugged-in USB or headset microphone if there is one, otherwise the iPhone's bottom microphone in its all-direction pattern (the back microphone faces the table when the phone lies screen-up).
- **Echo and noise reduction** (Settings → Microphone, off by default): Apple's speakerphone processing. It cuts echo and hiss but favours people within a metre or two.
- **How many people? (optional)**: the people button at the top right of the recording screen sets how many are speaking (Auto by default). It never stops you recording and can be changed any time before Stop. A known number helps speaker separation tell similar voices apart; it doesn't change the words transcribed.
- **Wrong number of speakers?**: on a meeting with a kept recording, choose how many people spoke and speaker separation runs again with that number (it's remembered for the meeting). Names stay with the voices that match ones you've named (a new voice must cover mostly the same lines); only new voices need naming.
- **Remember voices** (Settings → Speakers, off by default): when you name a speaker you can tick *Remember this voice*, only with their agreement. Their voiceprint is saved on the iPhone and later meetings suggest "Sounds like Priya?". After three confirmations, strong matches are named automatically ("Recognised"). Settings → Remembered voices lists who's saved and can forget them. Voiceprints are biometric (UK GDPR special category) data, so check with your Information Governance team before using this with colleagues.
- **Playing the recording**: the player only appears when it's needed. Tap **Play recording** at the top of a meeting, or tap a transcript line. While it plays, the full player (scrubber, speed, ×) sits at the bottom and the line being spoken is highlighted. A few seconds after you pause, it shrinks to a small pill in the corner on every tab; tap the pill to open it again, or × to close it.
- **Fixing speakers by hand**: hold a line → *Change speaker* to move it to another speaker or a **New speaker**. To fix a stretch where two voices were confused, tap **Select lines** above the transcript (or hold a line → *Select lines*). Tap lines to select them, or hold a line to select everything from the last one you tapped up to it, then tap **Change speaker** to move them all at once. The speaker list opens as a sheet, so it isn't disturbed by playback. Tapping a line plays just that line; *Play from here* carries on.
- **Apple Watch** (needs watchOS 10 or later): a Clear Notes app on the watch records a **voice note** or a **quick catch-up** with one tap. There's a **To-do** (or **Action**) button while recording. When you stop, the recording goes to the iPhone directly over Bluetooth or Wi-Fi, encrypted; if the iPhone isn't in reach, it waits on the watch ("1 waiting for iPhone"). The iPhone transcribes it from the audio (with the more accurate model if it's downloaded, otherwise Apple's on-device speech recognition), then writes the notes as usual; the meeting shows an **Apple Watch** chip. The watch's microphone is for one voice close by, not a room: record room meetings on the iPhone. **While the iPhone records**, the watch becomes its remote: the timer, **Action** and **Decision** (a tap on the wrist confirms each) and **Pause**/**Resume**, so you needn't touch the phone on the table.
- **Meeting reminders** (Settings → Calendar → Remind me when a meeting starts, off by default): a notification as each of today's and tomorrow's meetings with other people starts, unless it's already been recorded. On the iPhone, **Record** opens Clear Notes on that meeting. When the iPhone is locked or put away the reminder shows on Apple Watch, where **Record on watch** records the meeting on the watch and links it to the diary meeting. The meeting's name is left out unless you turn on **Show the meeting's name**, since anyone who can see your Lock Screen or watch can read it.
- **Menus**: every menu is a solid sheet that slides up from the bottom, with its options on cards: **⋯** and **Share** on a meeting, holding a meeting card, an action, a decision or a transcript line, the choices in Settings, and every "Are you sure?". The options that delete something are red and come last.
- **Recently deleted**: a meeting card's menu (hold the card) and ⋯ inside a meeting both offer two ways to delete: **Move to Recently deleted** (with **Undo** for a few seconds afterwards) or **Delete permanently** (gone straight away, recording and all). Meetings moved there stay in **Settings → Recently deleted** for 7 days, recording included, where they can be restored or deleted for good; after 7 days they're deleted for good automatically.
- **Playback**: a player bar on each meeting, with 1×/1.5×/2× speed. Tap any transcript line to hear that moment, or play a speaker's lines while naming them. **Settings → Keep recordings** sets how long audio is kept; **⋯ → Remove the audio** removes it sooner and keeps the transcript and notes. Recordings are excluded from backups.
- **Speaker separation**: after you finish, [FluidAudio](https://github.com/FluidInference/FluidAudio) (pyannote models running on the iPhone's Neural Engine) finds who spoke when. Word timings from the transcript split each line at speaker changes. Clips under 3 seconds are skipped, and short clips are padded with silence.
- **One-tap speaker naming**: tap a speaker to see what they said and name them. One name updates every line. Suggestions come from your own name, people invited to the meeting and people in earlier meetings. "Same person as" merges two voices, and holding a line moves it to another speaker. Once speakers are named, "I'll send it" is credited to whoever said it.
- **Calendar** (Settings → Calendar, off by default): reads today's events from Apple's Calendar app, including a work account added in iOS Settings. The home screen shows the meeting happening now, or the next one today, with one-tap recording. Meetings with other people invited come before blocks like WFH or Focus time. Only your main calendar (and each work account's own "Calendar") is used by default. Work accounts such as NHSmail often sync many colleagues' shared calendars, and apps can see them even when they're hidden in Apple's Calendar app. **Choose calendars** turns others on, such as a team calendar, and lists today's events under each calendar. Shared calendar names like "SMITH, Jane (Trust)" show as "Jane Smith". Events from a calendar other than your main one show its name. Recordings take the event's title and invited people, with you listed first whether you organised the meeting or were invited (by the calendar's name for you, or your name from Settings). Invited people are suggested first when naming speakers, an action owner like "Priya" becomes the invited "Priya Sharma" (when only one invitee has that first name), and the Teams link is kept for importing the Teams transcript later. Directory names such as "SMITH, Jane (Trust)" are tidied to "Jane Smith". All-day events, timed blocks of 6 hours or more ("Working from home 09:00–17:00", leave), and cancelled or declined events are ignored. Calendars shared with you can reach the iPhone through the work account, iCloud or a subscribed link. They stay off unless you turn them on, so other people's meetings aren't offered or linked. Only the title, invited names and Teams link are saved with the meeting. Outlook's own *Sync Calendars* also works where Intune allows it.
- **Last time** (meetings in a series): when a repeating calendar meeting, or one with the same title, was recorded on an earlier day, Today in your diary shows "Last time · Tue 27 Oct · 3 open actions" for the meeting on now or next. The recording screen has a **Last time** button, and the meeting's Overview has a **Last time** card. Each shows the previous summary, decisions and actions; tick actions off as people report them done.
- **Marking actions and decisions**: while recording, tap **Mark action** or **Mark decision** just after one is agreed, or say a phrase such as "action point", "action for Priya…" or "decision point". After the meeting, the 45 seconds before each mark become one action (open, with owner and due date if said, and a *Marked* label) or decision. Apple Intelligence writes it where available; otherwise the last promise or agreement before the mark is used.
- **Each action is checked against the conversation**: every possible action is read again with the two turns before it and the two after (a turn is everything one person says before someone else speaks). Only promises ("I'll send it") and requests someone accepted ("Can you…?" "Yes, by Friday") are kept; ideas ("we should…"), requests that were declined or passed to someone else, things already done and decisions aren't. Each kept action is rewritten to make sense on its own ("Send the revised rota to the ward managers", not "send it to them"), its owner is the person who will do it rather than whoever spoke, and a short line of context says why it's needed or who it's for, from what was said there. Deadlines become dates ("by Friday" said on a Wednesday → "by Fri 13 Nov"), and an action agreed early and recapped at the end is one action with every detail. Marked actions get context lines too. On iPhones without Apple Intelligence, rules do the check: a request only counts if the next person to speak accepts it. The context line can be edited with the action.
- **How keen it is on actions** (Settings → Actions): *Only what I mark*, *Marked plus clear commitments* (default: explicit promises and requests only, about one suggestion per five minutes) or *Everything it finds*. Suggestions never repeat a decision or a marked action, and repeats across a long meeting are merged.
- **Decision or action?** A suggested action has a *Decision* button. Hold any action to make it a decision, or hold a decision to make it an action.
- **Your own notes** alongside the transcript, with quick **Action** and **Decision** buttons that add time-stamped lines.
- **AI notes on the device**:
  - On iPhones with Apple Intelligence (iOS 26+), the on-device Foundation Models framework writes a title, summary, decisions and actions. Summary points that the model runs together on one line are split into separate bullets, including in older meetings. Long meetings are processed in parts (about 10–20 minutes for a two-hour meeting with the app open). Each part is saved as soon as it's written, so if iOS pauses Clear Notes the notes carry on from the next part instead of starting again. The processing card shows "Part 12 of 38" (the meeting list shows "Notes 12/38"), and the screen stays on while it's showing. On iOS 26, the steps that read the recording (the more accurate transcript and speaker identification) can carry on after you leave the app, with progress in the Dynamic Island and on the Lock Screen (Settings → After recording turns this off). That ends without an error once those steps are done, because Apple Intelligence won't write notes in the background. If you leave while notes are being written, they pause rather than settle for basic ones, and finish when Clear Notes is opened. The more accurate transcript pass is tried at most twice per meeting.
    - When the system is busy (Apple limits apps in the background most), it waits and retries. If Clear Notes is in the background, the notes finish the next time you open it.
    - A part that's too long is split in two. A part the model declines, such as one Apple's safety filter blocks, gets basic extraction instead.
    - If Apple Intelligence can't finish at all, you get basic notes. *About these notes* says why and offers *Try Apple Intelligence again*.
  - On other iPhones, a rules-based extractor finds commitments ("Priya will send… by Friday"), decisions ("we agreed…") and lines you marked in your notes.
- **Notes that read like a page**: summary, **topics with time ranges** (tap one to jump to that point in the transcript) and decisions on one surface.
- **Lock Screen controls while recording**: the Lock Screen and Dynamic Island show the recording timer with **Pause**/**Resume**, **Action** and **Decision** buttons, so you can mark moments without unlocking. It shows no meeting title or names, because anyone nearby can see the Lock Screen. While paused nothing is recorded or transcribed, but the microphone stays open (the orange dot stays on), because iOS doesn't let an app in the background start the microphone again. If a phone call takes the microphone, open Clear Notes to resume. Live Activities can be turned off in iOS Settings → Clear Notes.
- **Minutes** (Minutes tab): formal minutes written the way a minute-taker would. They have the title, date and time, who was present (named speakers), and a numbered item for each part of the meeting, written in the third person, past tense and reported speech ("Priya reported that…", "Concerns were raised about…"). Each item lists what was agreed and the actions under the part of the meeting where they came up, and a summary of actions comes at the end. Speakers who aren't named aren't attributed ("It was noted that…"). They're written on request on this iPhone (Apple Intelligence in its mode for transforming text you supply, or the meeting's key points without it). Each item is saved as soon as it's written, and the screen stays on while they're written. If you leave Clear Notes, they pause rather than fall back to key points, and carry on from the next item when you're back. They're plain text, so they paste cleanly into an email, Word or Teams, and you can edit, copy and share them. Only accepted actions are included.
- **Record** is in the middle of the tab bar at the bottom, so it's always one tap away and doesn't cover the list. It asks **what you're recording**: the meeting in your diary that's on now (one tap), another of today's diary meetings, or something that isn't in your diary:
  - **Quick catch-up**: a chat with one or two people. It asks who it's with (recent people first; pick, skip or change later), expects two voices and is called "Catch-up with Tom Ellis". Its notes are lighter: one Summary tab with what you covered, what was agreed and the actions. Catch-ups with the same person link up like a meeting series ("3 with Tom", Last time). Minutes are there if you ask for them.
  - **Voice note**: just you. No speaker step (so it's ready sooner and no voice profiles are made), one **Mark to-do** button, and no consent reminder. You get a title from what you said, a short note and a to-do list to tick off.
  - **Other meeting**: a meeting that isn't in your diary, with full notes and minutes.
- **Today in your diary** on the home screen (with Use my calendar on), below the Today / This week / All tiles. Folded, it's one line ("4 meetings · 1 recorded · next 14:30") plus the meeting on now with its Record button; tap it to see each of today's meetings with other people, marked **Recorded** (tap to open), **Record** (on now), **Later** or **Not recorded**, and Last time for the one on now or next. The list of meetings can be filtered: **All · Diary · Catch-ups · Voice notes**, and each card shows its type. On a meeting, **⋯ → Change type** or **Link to a diary meeting** fixes one recorded as the wrong type.
- **Light and dark, and a colour**: Clear Notes matches the iPhone's appearance by default. Settings → Appearance can make it always Light or always Dark, and choose the app's colour: **Teal** (default), **Ocean**, **Sage**, **Amber** or **Graphite**. The colour sets buttons, highlights, your avatar and the first speaker's colour, in light and dark; meeting-type colours shift so they never clash with it, and with Sage decisions turn amber. Record is always red. The recording screen follows the same settings.
- **Finding meetings**: the search box on the Meetings screen searches titles, summaries, transcripts, your notes, speaker names and actions. Older meetings are grouped by month. The **calendar** button (top right) shows a month calendar with a dot on each day that has a recording; tap the month to jump to any month or year, and tap a day to see its meetings. A meeting that's part of a series shows "*N* in this series", and its Last time card has **All in this series**, which lists every recording newest first.
- **Reviewing suggestions**: each suggested action has **Accept** and **Dismiss**. The **⋯** button holds *It's a decision*, *Edit or assign* and *Show source*. **Accept all** and **Dismiss all** above the list clear every suggestion at once, after you confirm.
- **Assigning actions**: tap an action (or its **Assign** chip, or hold it → *Edit or assign*) to change what needs doing, who's doing it and when. Pick from you, named speakers, people invited and existing owners, or type a name. Type a due date ("by Friday") or pick one from a calendar. Saving a suggested action accepts it. Actions from last time can be assigned in the same way.
- **Share a meeting with another Clear Notes user**: Share → *Share meeting with a Clear Notes user* makes one `.clearnotes` file to send by AirDrop, Messages or Mail. The other person taps it, chooses *Open in Clear Notes*, previews it and imports their own copy. Importing the same meeting again offers *Update my copy* (their own notes are kept) or *Keep both*.
  - **Always in the file:** the transcript with speaker names, summary, topics, decisions, actions (dismissed suggestions aren't shared) and minutes.
  - **Only if you tick it:** your private notes and the recording.
  - **Never in the file:** remembered voiceprints.
  - **Optional password:** encrypts the file with AES-256-GCM, using a key derived from the password with PBKDF2, 600,000 rounds. Tell the person the password another way.
  - **Readable copy:** the minutes (or the notes) can go along as text for people without the app.
  - **Format:** documented in [docs/meeting-file-format.md](../docs/meeting-file-format.md). It's also the planned upload format for a future web app.
  - **Managed work apps** (e.g. NHSmail's Outlook under Intune) may refuse the file.
- **One-tap follow-ups**: *List actions*, *Write follow-up email* and *Draft project plan*. Drafts are built only from the meeting's own notes and accepted actions. On iPhones with Apple Intelligence they're rewritten into natural prose on the device, with an instruction to keep every fact. They're editable, with Copy and Share.
- **Talk time**: each speaker's share of the conversation, as percentages and a coloured bar.
- **Action review**: AI suggestions arrive as *To review*, and you accept or dismiss each one. Every action links back to the transcript line it came from (**Source**).
- **Actions stay with their meeting**: each meeting card shows how many actions are open or waiting for review, and they're reviewed and ticked off inside the meeting (or on a later meeting's Last time card). There's no separate Actions tab. The home screen counts meetings today, this week and in total.
- **Search** across titles, summaries, notes and transcripts.
- **Share or copy** a meeting as Markdown (summary, decisions, actions, notes and transcript).
- **Consent reminder** before each recording, which you can turn off.

## Requirements

- A Mac with **Xcode 16** or later. Use **Xcode 26** to get Apple Intelligence notes and the Liquid Glass look; older Xcode builds fall back to basic extraction and translucent materials automatically.
- An internet connection the first time you build (Xcode fetches the FluidAudio package) and the first time speakers are identified (the speaker models, roughly tens of MB, download once).
- An iPhone running **iOS 17** or later. Apple Intelligence notes need a supported iPhone on iOS 26+.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project: `brew install xcodegen`.

## Run it on your iPhone

```bash
cd ios
xcodegen generate        # creates ClearNotes.xcodeproj from project.yml
open ClearNotes.xcodeproj
```

1. In Xcode, select the **ClearNotes** target, open **Signing & Capabilities**, and choose your Team. A free Apple ID works for running on your own phone.
2. If Xcode says the bundle ID is taken, change it (e.g. `com.yourname.clearnotes`).
3. Plug in your iPhone (or pair it over Wi-Fi), select it as the run destination, and press **Run** (⌘R).
4. On the iPhone, the first time: **Settings → General → VPN & Device Management** → trust your developer certificate. Developer Mode may also need to be turned on (**Settings → Privacy & Security → Developer Mode**).

Run the unit tests with **⌘U**.

The simulator has no real microphone input for speech, so test capture on a real iPhone.

## TestFlight

GitHub Actions builds, tests and uploads the app to TestFlight, so no Mac is needed. See [TESTFLIGHT.md](TESTFLIGHT.md) for the one-time setup.

## Project layout

```
ios/
├── project.yml                  XcodeGen spec (targets, Info.plist keys, permissions)
├── ClearNotes/
│   ├── App/                     App entry and tab bar
│   ├── Models/                  SwiftData models: Meeting, ActionItem
│   ├── Services/
│   │   ├── MeetingRecorder      Mic capture + on-device speech (with word timings) + temporary 16 kHz audio
│   │   ├── SpeakerSeparator     FluidAudio speaker separation, behind a protocol
│   │   ├── SpeakerAssigner      Splits the transcript into speaker turns using word timings
│   │   ├── RecordingStore       Temporary audio: excluded from backup, protected, always deleted
│   │   ├── NotesEnhancer        Protocol + picks the best on-device engine
│   │   ├── AppleIntelligenceEnhancer   Foundation Models (iOS 26+)
│   │   ├── HeuristicEnhancer    Rules-based fallback
│   │   ├── MeetingProcessor     Speakers, then notes; resumes after relaunch; keeps reviewed actions
│   │   ├── MinutesWriter        Formal minutes in reported speech, built from topics, decisions and actions
│   │   ├── RecordingLiveActivity  Starts and updates the Lock Screen controls
│   │   └── MarkdownExporter     Share or copy text
│   └── Views/                   Home, Recording, Meeting detail, Speaker naming, Settings
│       └── Components/          Design system: Theme, glass, PillTabs, Avatar, ActionCard…
├── Shared/                      Lock Screen activity state and its button actions; watch recording details (shared by targets)
├── LiveActivity/                Lock Screen and Dynamic Island extension (WidgetKit)
├── Watch/                       Apple Watch app: records on the watch, sends to the iPhone (WatchConnectivity)
├── WatchComplication/           The watch-face Record button (WidgetKit); not built yet, see project.yml
└── ClearNotesTests/             Unit tests for extraction, speaker splitting, formatting and source linking
```

## Known limits in Phase 1

- **Speaker separation works best with 2–6 people in a quiet room.** It gets worse when people talk over each other, the room echoes, or someone is on a speakerphone far from the iPhone. Speakers are identified after the meeting, not live.
- **Processing waits for the iPhone to be unlocked.** Recordings are protected with iOS's strongest file protection, so they can't be read while the iPhone is locked. The more accurate transcript pass and speaker identification wait for it to be unlocked, then carry on by themselves; they're never marked as failed because of the lock.
- **Notes are written fastest with Clear Notes open.** iOS limits Apple Intelligence for apps in the background, so a long meeting's notes may pause until you open the app again; nothing already written is lost.
- **Apple Watch recordings are for one voice nearby.** The watch's microphone doesn't pick up a room like the iPhone's. Whether recording carries on with your wrist lowered depends on watchOS keeping Clear Notes running; keep the app open if a recording stops early. Recordings reach the iPhone when it's in reach and are transcribed when Clear Notes next runs there.
- **Very long meetings use more memory** while speakers are identified (about 230 MB per hour of audio).
- **Microphone capture only.** For online calls, run the call on speaker (or another device) near the iPhone. iOS doesn't let apps capture other apps' call audio.
- **Rules-based extraction is basic.** It finds clear commitments and decisions but will miss some and suggest some false positives. This is why every suggestion is reviewed.
- **Not for clinical use.** Don't record consultations or patient information. See `docs/market-research.md` for the NHS guidance on ambient scribes.
