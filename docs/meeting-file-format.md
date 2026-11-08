# Clear Notes meeting file (`.clearnotes`), format version 1

This is how a meeting is shared between Clear Notes users. It is also the planned upload format for a future Clear Notes web app (see the roadmap). The app writes and reads it in `ios/ClearNotes/Services/MeetingFile.swift`.

- **Type:** `com.clearnotes.meeting`, conforming to `public.data` and `public.content`
- **Extension:** `.clearnotes`
- **MIME type:** `application/vnd.clearnotes.meeting`

## What's in it

**Always included**
- Title, date, duration and invited people
- The transcript, with speaker names
- Summary, topics and decisions
- Actions, with owner, due date and status
- Minutes, if they've been written

**Included only if the sender ticks it**
- Their private notes
- The recording

**Never included**
- Remembered voiceprints (biometric data)
- Word timings
- The calendar event's Teams link
- Calendar series IDs

## Layout

All integers are big-endian.

| Bytes | Meaning |
|---|---|
| 8 | Magic: `CLRNOTES` (ASCII) |
| 1 | Container version: `1` |
| 1 | Flags: bit 0 set = password-protected |
| 16 | *Protected only:* random salt |
| 4 | *Protected only:* PBKDF2 iteration count (the app uses 600,000; readers accept up to 10,000,000) |
| … | Records, until the end record |

Each record is:

| Bytes | Meaning |
|---|---|
| 1 | Type: `1` meeting, `2` recording piece, `0` end |
| 4 | Length of the body |
| n | Body |

The records come in this order:
1. **One meeting record**: the meeting as UTF-8 JSON (below).
2. **Recording pieces** (zero or more), each holding at most 1 MiB of the recording.
3. **One end record**: 8 bytes of total recording size, then the 32-byte SHA-256 of the recording. With no recording, these are 0 and the hash of nothing.

A reader checks the size and hash against the pieces it received, so a damaged or cut-short file is refused.

### Password protection

- **Key:** PBKDF2-HMAC-SHA256 of the UTF-8 password with the salt and iteration count from the header. This gives a 256-bit key.
- **Each record body** is AES-256-GCM in CryptoKit's *combined* form: 12-byte nonce, then the ciphertext, then the 16-byte tag.
- **Authenticated data** is the ASCII `clearnotes`, then the record type (1 byte), then the record's position counted from 0 (4 bytes). Records can't be reordered, swapped or moved between files.
- If the first record fails to open, the password is wrong. If a later one fails, the file is damaged.
- Without a password, record bodies are the plain bytes.

## Meeting JSON

- **Dates** are ISO 8601.
- **Keys** are sorted.
- **IDs** are UUID strings, except speaker IDs.
- **Optional fields** may be missing or `null`.

| Field | Type | Notes |
|---|---|---|
| `formatVersion` | integer | `1`. Readers refuse newer versions and ask the user to update. |
| `meetingID` | UUID | The same for every copy of a meeting, so importing it again can update a copy. |
| `title` | string | |
| `date` | date | When the meeting started. |
| `duration` | number | Seconds. |
| `sharedBy` | string? | The sender's name from Settings. |
| `sharedAt` | date | |
| `invited` | [string] | |
| `speakers` | [{`id`, `number`, `name`?}] | `id` is referenced by transcript lines. Unnamed speakers show as "Speaker *number*". |
| `transcript` | [{`id`, `start`, `end`, `text`, `speakerID`?}] | Times are seconds from the start of the meeting. |
| `summary` | string | "- " bullet lines. |
| `topics` | [{`title`, `start`, `end`, `points`}] | |
| `decisions` | [string] | |
| `actions` | [{`text`, `owner`?, `due`?, `status`, `sourceLineID`?, `context`?}] | `status` is `suggested`, `open`, `done` or `dismissed`. Dismissed actions aren't shared. `sourceLineID` is a transcript line's `id`. `context` (from 0.3) is a short line of detail, e.g. who it's for; older files leave it out. |
| `minutes` | string? | Plain-text minutes (numbered items, `Agreed:` and `Action:` lines). |
| `kind` | string? | What was recorded: `meeting`, `catchUp` (a quick catch-up; `invited` holds who it was with) or `voiceNote`. Missing means `meeting`. |
| `privateNotes` | string? | Only when the sender chose to include them. |
| `notesCaveat` | string? | Why some notes are basic, if they are. |
| `notesSource` | string? | What wrote the notes, e.g. Apple Intelligence. |
| `recording` | {`byteCount`, `fileExtension`}? | Present when the file contains the recording. `fileExtension` is `caf`: 16 kHz mono 16-bit PCM. |

## Changing the format

- **New optional fields** can be added without changing `formatVersion`. Older readers ignore them.
- **Renaming or removing a field,** or changing its meaning, needs a new `formatVersion`. So does changing the record layout or encryption.
