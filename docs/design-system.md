# Clear Notes — Design System v2

v1 looked like a stock iOS settings screen: grey grouped lists, hairline rows, segmented controls and a flat indigo. v2 aims for the polish of current note-taking apps (Granola, Otter, Fathom) and the iOS 26 visual language:

- **Calm, bright surfaces** over a soft colour glow, not grey lists
- **People first**: coloured speaker avatars appear on cards, in transcripts and on actions
- **Bold typography** with clear hierarchy, plus small uppercase "eyebrow" labels
- **Glass for controls, solid cards for content.** On iOS 26 floating controls use Liquid Glass (`glassEffect`); on iOS 17–18 they fall back to `.ultraThinMaterial`
- **One signature gradient** (violet → blue) for AI and brand moments, and one warm gradient (coral → pink) for recording

## Tokens

### Colour

| Token | Light | Dark | Use |
|---|---|---|---|
| `background` | `#F6F6FA` | `#0A0A0F` | Screen background |
| `surface` | `#FFFFFF` | `#16161D` | Cards |
| `surfaceRaised` | `#FFFFFF` | `#1E1E27` | Selected pill, sheets |
| `stroke` | `rgba(15,15,30,.06)` | `rgba(255,255,255,.07)` | 1px card outline |
| `textPrimary` | `#0E0E14` | `#F4F4F8` | |
| `textSecondary` | `#6B6B78` | `#9A9AA8` | |
| `textTertiary` | `#A3A3AF` | `#5C5C68` | Placeholders, hints |
| `brand` | from the chosen colour (`AppAccent`) | | Accent / tint. Teal by default: `#0F9C8C` light, `#3CCFBE` dark. Also Ocean, Sage, Amber, Graphite (Settings → Appearance) |
| `brandGradient` | from the chosen colour, e.g. Teal `#14B8A6 → #2E8FD8` (135°) | same | AI badges, primary buttons |
| `onBrand` | white, or near-black on Amber and dark Graphite | | Text and symbols on `brand` |
| `recordGradient` | `#FF7A59 → #FF3D71` (135°) | same | Record button, live state |
| `success` | `#22C55E` | `#30D158` | Done |
| `warning` | `#F59E0B` | `#FFB020` | Due dates |
| Glow blobs | violet `#8B7BFF` 28%, sky `#5AB8FF` 22%, peach `#FFB38A` 20% | 22% / 16% / 10% | Blurred (radius 80) behind the top of each screen |

**Speaker palette** (used in order, both modes): violet `#7C5CFF`, teal `#14B8A6`, orange `#FB923C`, pink `#EC4899`, blue `#3B82F6`, lime `#84CC16`, amber `#EAB308`, red `#EF4444`.

### Type (SF Pro)

| Style | Spec |
|---|---|
| Display | 34 bold, tracking −0.6 (screen titles) |
| Title | 28 bold, tracking −0.4 (meeting title) |
| Timer | 64 thin, monospaced digits |
| Headline | 17 semibold |
| Body | 17 regular, line height 1.35 |
| Subhead | 15 regular |
| Footnote | 13 regular |
| Eyebrow | 12 semibold, UPPERCASE, tracking +0.8, `textSecondary` |

### Shape and spacing

- Card radius **24** (continuous), inner elements **14–16**, pills fully rounded
- Screen gutter **20**, stack spacing **12** (inside cards) / **16** (between cards)
- Card: `surface` fill, 1px `stroke`; light mode adds shadow `0 8 24 rgba(30,30,60,.06)`

## Components

| Component | Description |
|---|---|
| `GlowBackground` | `background` colour with three blurred colour blobs across the top ~300pt |
| `Eyebrow` | Uppercase label above a title or section |
| `Card` | Content card; optional header row (icon in a 28pt tinted rounded square + headline + trailing accessory) |
| `PillTabs` | Replaces segmented controls. A glass track (capsule) with a raised, sliding thumb (`matchedGeometryEffect`). Optional count badge per tab |
| `Avatar` | Circle with white initials on the speaker colour. Sizes 24/32/44/72. Unnamed speakers show their number on a tinted circle with a dashed ring |
| `AvatarStack` | Overlapping avatars (−8pt) with a 2pt `surface` ring, "+N" overflow |
| `Chip` | Small capsule, tint at 12% fill + tint text; icon optional |
| `StatTile` | Small card: eyebrow label, big number (28 bold), trend or hint line |
| `GradientIcon` | SF Symbol on a 28pt rounded square filled with `brandGradient` (AI content) |
| `RecordButton` | Floating capsule, 60pt tall, `recordGradient`, white mic in a translucent white circle, label "Record", coloured shadow |
| `GlassCircleButton` | 40pt glass circle for close / more / search |
| `PrimaryButton` | Capsule filled with `brandGradient`, white semibold label |
| `SecondaryButton` | Capsule with `textPrimary` at 6% fill |

## Screens

### 1. Home
- `GlowBackground`
- Header: eyebrow date ("THURSDAY 30 OCTOBER"), Display greeting ("Good morning"), trailing 40pt avatar "Me"
- Search capsule (glass): magnifier + "Search meetings, people, actions"
- **Stats row** of 3 tiles: *To review* (count, brand), *Open actions* (count), *This week* (hours of meetings)
- Sections with eyebrow headers: "TODAY", "THIS WEEK", "EARLIER"
- **Meeting card**: top row "10:02 · 34 min" (footnote, secondary) + trailing status (a "Processing" shimmer chip, or a lock icon for on-device). Title (headline, 2 lines). Summary (subhead, secondary, 2 lines). Bottom row: `AvatarStack` of speakers + speaker names text ("Priya, Tom +2"), trailing chip "3 actions"
- Floating `RecordButton`, bottom centre, above the tab bar
- Tab bar: system TabView (becomes Liquid Glass on iOS 26). Tabs: Meetings (`waveform`), Actions (`checklist`, badge), Settings (`gearshape`)

### 2. Recording (always dark, immersive)
- Background `#07070B` with a large blurred `recordGradient` glow behind an **orb** that scales with the microphone level
- Top: `GlassCircleButton` close, centre glass status pill: pulsing red dot + "REC" + "On-device" lock
- Orb (180pt): 3 concentric circles of `recordGradient` at 100/40/15% opacity, scaled by level. Timer (64 thin) below
- `PillTabs`: Transcript / Notes
- Transcript: lines with timestamps; newest line in secondary colour with a blinking caret; top edge fades out with a gradient mask. Hint at the top: "Speakers are identified when you finish"
- Notes: plain editor + chips "+ Action", "+ Decision", "+ Moment"
- Bottom glass bar: pause (56pt glass circle), **Finish** capsule (`recordGradient`)

### 3. Meeting detail
- `GlowBackground`; inline nav bar with glass back / share / more buttons
- Eyebrow date, Title, meta chips: duration, speaker count, "On-device" lock
- **Speakers strip**: horizontally scrolling 44pt avatars with name below; unnamed ones show "Speaker 2" and a brand-coloured "Tap to name". Tap opens the naming sheet
- If any speaker is unnamed, a hint card appears: "Name speakers to improve notes"
- **Processing state** replaces the content with a card listing steps and checkmarks: "Transcribed ✓", "Identifying speakers…", "Writing summary"
- `PillTabs`: Overview · Actions (badge) · Transcript · Notes

**Overview**: Summary card (GradientIcon sparkles, "Summary", bullet list with brand dots). Decisions card (numbered circles). "3 actions to review" card with avatars of owners and a chevron. Footnote: "Written on this iPhone by Apple Intelligence. Check before sharing."

**Actions**: action cards with the owner `Avatar` (speaker colour when the owner matches a named speaker), text (headline weight for open, strikethrough for done), chips (due date, "Source"), suggested ones carry an "AI" gradient badge and **Accept** (PrimaryButton, small) / **Dismiss** (SecondaryButton, small). "+ Add action" row at the bottom.

**Transcript**: conversation layout, one block per speaker turn: `Avatar` 32 + speaker name (semibold, speaker colour) + timestamp (footnote, tertiary), text below indented to the name. Tap a name to rename; long-press a turn for "Change speaker".

**Notes**: card with an editor.

### 3a. Overview as a document (v2.1)
Replaces the stack of Summary / Decisions cards with **one document surface** (a single `Card`, padding 22), so the notes read like a page. The v2 tokens, colours and type stay the same.

1. **Summary**: `GradientIcon` sparkles + "Summary" (Title 3 bold), bullets with brand dots
2. Hairline divider
3. **Topics**: `GradientIcon` list icon + "Topics". One row per topic: a monospaced time-range chip ("0:00–10:12", brand tint) and the topic title (headline), then 1–3 bullet points (subhead, secondary). Tapping a topic opens the Transcript at that time and highlights the first line
4. Hairline divider
5. **Decisions**: numbered green circles (as before)

Below the document:
- **Follow-ups** card: three rows separated by hairlines, each a 40pt tinted icon tile + title + subtitle + chevron:
  - *List actions*: "Owners and due dates, ready to paste" (`checklist`, brand)
  - *Write follow-up email*: "A thank-you with decisions and next steps" (`envelope`, teal `#14B8A6`)
  - *Draft project plan*: "Goals, workstreams and timeline" (`doc.text`, orange `#FB923C`)
- Then the "N actions to review" card and the source footnote (as before)

### 3b. Talk time (in the Speakers card)
- Under each avatar's name, the speaker's share of talk time ("42%", caption, secondary)
- Under the avatar row, a 8pt-tall rounded **stacked bar** with one segment per speaker in their colour (2pt gaps), plus a footnote "Talk time · 34 min"

### 3c. Follow-up sheet (large detent)
- Title row: tinted icon tile + the follow-up name, close button
- Status line: "Written on this iPhone by Apple Intelligence" (or "From your meeting notes" for templates)
- Editable draft in a card (body text; email has a "Subject:" first line)
- Bottom bar (glass): **Copy** (SecondaryButton), **Share** (PrimaryButton), and a "Rewrite" (`arrow.clockwise`) GlassCircleButton
- While writing: skeleton lines and "Writing on this iPhone…"

### 4. Speaker naming sheet (medium detent)
- 72pt avatar in the speaker colour, title "Who is Speaker 2?"
- Eyebrow "THEY SAID", then 2 quote cards (italic, with timestamps) to help recognise the voice
- Name field (glass capsule) with a **Save** PrimaryButton
- Eyebrow "SUGGESTIONS": one-tap chips: "Me", then names used in earlier meetings and action owners. One tap names every line from this speaker and closes the sheet
- Eyebrow "SAME PERSON AS", then avatars of the other speakers (merges the two)

### 5. Actions tab
- `GlowBackground`, Display title "Actions", subtitle "7 open across 4 meetings"
- `PillTabs`: To review (count) · Open (count) · Done
- Action cards as in the meeting detail, plus a footer row with a meeting chip (waveform icon + meeting title)

### 6. Settings
- Header card: app icon, "Clear Notes", "Private by design: everything stays on this iPhone"
- Grouped cards (not the stock form): Privacy (on-device transcription, consent reminder, identify speakers), Speaker models (status, size, Download button), This iPhone (capability status rows), About
