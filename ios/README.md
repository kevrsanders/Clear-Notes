# Clear Notes for iPhone (Phase 1)

A native SwiftUI app that transcribes meetings on the iPhone, works out who said what, and turns it into a summary, decisions and actions. There is no meeting bot and no meeting data goes to a server. Recordings stay on the iPhone for playback and are deleted automatically after the period chosen in Settings (7 days by default, or as soon as notes are ready).

Design: see [docs/design-system.md](../docs/design-system.md) and the mockups in [docs/mockups/v2](../docs/mockups/v2) (light and dark).

## Features

- **Live capture**: big timer, level meter and a live transcript. Pause and resume. Recording continues when the screen locks, and pauses automatically for phone calls.
- **On-device transcription**: on iOS 26 it uses Apple's SpeechAnalyzer/SpeechTranscriber, a long-form model built for meetings and people further from the phone. On earlier versions it uses the older speech recogniser with `requiresOnDeviceRecognition`; a setting (on by default) refuses to record if your language can't be transcribed on the device.
- **Distant voices**: the transcriber gets a gentle automatic boost (up to about +12 dB, only while someone is speaking, with a limiter near full scale). The kept recording is the untouched microphone audio. The app uses a plugged-in USB or headset microphone if there is one, otherwise the iPhone's bottom microphone in its all-direction pattern (the back microphone faces the table when the phone lies screen-up).
- **Echo and noise reduction** (Settings → Microphone, off by default): Apple's speakerphone processing. It cuts echo and hiss but favours people within a metre or two.
- **Wrong number of speakers?**: on a meeting with a kept recording, choose how many people spoke and speaker separation runs again with that number.
- **Playback**: a player bar on each meeting, with 1×/1.5×/2× speed. Tap any transcript line to hear that moment, or play a speaker's lines while naming them. **Settings → Keep recordings** sets how long audio is kept; "Delete recording" removes it sooner. Recordings are excluded from backups.
- **Speaker separation**: after you finish, [FluidAudio](https://github.com/FluidInference/FluidAudio) (pyannote models running on the iPhone's Neural Engine) finds who spoke when. Word timings from the transcript split each line at speaker changes. Clips under 3 seconds are skipped, and short clips are padded with silence.
- **One-tap speaker naming**: tap a speaker to see what they said and name them. One name updates every line. Suggestions come from your own name and from people in earlier meetings. "Same person as" merges two voices, and long-pressing a line moves it to another speaker. Once speakers are named, "I'll send it" is credited to whoever said it.
- **Your own notes** alongside the transcript, with quick **Action** and **Decision** buttons that add time-stamped lines.
- **AI notes on the device**:
  - On iPhones with Apple Intelligence (iOS 26+), the on-device Foundation Models framework writes a title, summary, decisions and actions. Long meetings are processed in chunks.
  - On other iPhones, a rules-based extractor finds commitments ("Priya will send… by Friday"), decisions ("we agreed…") and lines you marked in your notes.
- **Notes that read like a page**: summary, **topics with time ranges** (tap one to jump to that point in the transcript) and decisions on one surface.
- **One-tap follow-ups**: *List actions*, *Write follow-up email* and *Draft project plan*. Drafts are built only from the meeting's own notes and accepted actions. On iPhones with Apple Intelligence they're rewritten into natural prose on the device, with an instruction to keep every fact. They're editable, with Copy and Share.
- **Talk time**: each speaker's share of the conversation, as percentages and a coloured bar.
- **Action review**: AI suggestions arrive as *To review*, and you accept or dismiss each one. Every action links back to the transcript line it came from (**Source**).
- **Actions tab**: every open action across all meetings, with a badge count.
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
│   │   └── MarkdownExporter     Share or copy text
│   └── Views/                   Home, Recording, Meeting detail, Speaker naming, Actions, Settings
│       └── Components/          Design system: Theme, glass, PillTabs, Avatar, ActionCard…
└── ClearNotesTests/             Unit tests for extraction, speaker splitting, formatting and source linking
```

## Known limits in Phase 1

- **Speaker separation works best with 2–6 people in a quiet room.** It gets worse when people talk over each other, the room echoes, or someone is on a speakerphone far from the iPhone. Speakers are identified after the meeting, not live.
- **Very long meetings use more memory** while speakers are identified (about 230 MB per hour of audio).
- **Microphone capture only.** For online calls, run the call on speaker (or another device) near the iPhone. iOS doesn't let apps capture other apps' call audio.
- **Rules-based extraction is basic.** It finds clear commitments and decisions but will miss some and suggest some false positives. This is why every suggestion is reviewed.
- **Not for clinical use.** Don't record consultations or patient information. See `docs/market-research.md` for the NHS guidance on ambient scribes.
