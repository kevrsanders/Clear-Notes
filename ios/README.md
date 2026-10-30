# Clear Notes for iPhone (Phase 1)

A native SwiftUI app that transcribes meetings on the iPhone and turns them into a summary, decisions and actions. There is no meeting bot, nothing goes to a server, and audio is never saved.

## Features

- **Live capture**: big timer, level meter and a live transcript. Pause and resume. Recording continues when the screen locks, and pauses automatically for phone calls.
- **On-device transcription**: uses Apple's speech recogniser with `requiresOnDeviceRecognition`. A setting (on by default) refuses to record if your language can't be transcribed on the device.
- **Your own notes** alongside the transcript, with quick **Action** and **Decision** buttons that add time-stamped lines.
- **AI notes on the device**:
  - On iPhones with Apple Intelligence (iOS 26+), the on-device Foundation Models framework writes a title, summary, decisions and actions. Long meetings are processed in chunks.
  - On other iPhones, a rules-based extractor finds commitments ("Priya will send… by Friday"), decisions ("we agreed…") and lines you marked in your notes.
- **Action review**: AI suggestions arrive as *To review*, and you accept or dismiss each one. Every action links back to the transcript line it came from (**Source**).
- **Actions tab**: every open action across all meetings, with a badge count.
- **Search** across titles, summaries, notes and transcripts.
- **Share or copy** a meeting as Markdown (summary, decisions, actions, notes and transcript).
- **Consent reminder** before each recording, which you can turn off.

## Requirements

- A Mac with **Xcode 16** or later. Use **Xcode 26** to get Apple Intelligence notes; older Xcode builds fall back to basic extraction automatically.
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

## Project layout

```
ios/
├── project.yml                  XcodeGen spec (targets, Info.plist keys, permissions)
├── ClearNotes/
│   ├── App/                     App entry and tab bar
│   ├── Models/                  SwiftData models: Meeting, ActionItem
│   ├── Services/
│   │   ├── MeetingRecorder      Mic capture + on-device speech, chunked into time-stamped segments
│   │   ├── NotesEnhancer        Protocol + picks the best on-device engine
│   │   ├── AppleIntelligenceEnhancer   Foundation Models (iOS 26+)
│   │   ├── HeuristicEnhancer    Rules-based fallback
│   │   ├── MeetingProcessor     Stores AI results; keeps actions you already reviewed
│   │   └── MarkdownExporter     Share or copy text
│   └── Views/                   Meetings, Recording, Meeting detail, Actions, Settings
└── ClearNotesTests/             Unit tests for extraction, formatting and source linking
```

## Known limits in Phase 1

- **No speaker names.** Apple's on-device recogniser doesn't separate speakers.
- **Microphone capture only.** For online calls, run the call on speaker (or another device) near the iPhone. iOS doesn't let apps capture other apps' call audio.
- **Rules-based extraction is basic.** It finds clear commitments and decisions but will miss some and suggest some false positives. This is why every suggestion is reviewed.
- **Not for clinical use.** Don't record consultations or patient information. See `docs/market-research.md` for the NHS guidance on ambient scribes.
