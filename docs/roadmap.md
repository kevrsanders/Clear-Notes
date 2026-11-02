# Clear Notes — Roadmap (Phase 2 onwards)

_Planning notes, not yet built. Last updated 2 November 2026 (decisions recorded)._

Phase 1 (done) is a private, on-device iPhone app: capture, transcription, speakers, notes, actions, playback and voice memory. Next we connect it to where work actually happens, mainly Microsoft 365, while keeping the privacy-first design.

## Guiding principles

1. **No server unless it's needed.** Most Microsoft 365 features can be called straight from the iPhone with the user's own sign-in (delegated permissions). A back end is only needed for things that must run when the phone isn't involved, such as a Teams bot or a team-wide service.
2. **Least privilege.** Ask only for the permissions a feature needs, and only when the user turns that feature on.
3. **The user sends things out.** Nothing is pushed to Microsoft 365 automatically. The user reviews and taps *Send to Planner* or *Send to To Do*.
4. **Governance first.** Each integration changes the data flow, so the DPIA needs updating and Information Governance (IG) needs to approve it before use with real meetings.

---

## Phase 2a: Microsoft 365 from the iPhone (no server)

### Foundation: sign in with Microsoft
- **MSAL for iOS** (Microsoft Authentication Library) with the **Microsoft Authenticator broker**. This gives single sign-on with NHSmail or the organisation's account, and works with Conditional Access and Intune app protection.
- An **app registration in Microsoft Entra ID**, owned by your organisation (see *Decisions* below).
- Sign-in is optional. The app keeps working fully offline without it.

### Send actions to Microsoft To Do
- *Send to To Do* on an action, or *Send all accepted actions*.
- Graph: `POST /me/todo/lists/{listId}/tasks` (delegated **Tasks.ReadWrite**). It sets the title, due date and a note with the meeting name. `linkedResources` links back to the meeting in Clear Notes.
- The user picks a list once, e.g. "Meetings".
- Two-way: optionally mark actions done in Clear Notes when they're completed in To Do (`GET` the task, or delta queries).

### Send actions to Planner
- Choose a **plan** and **bucket** (remembered per meeting series), then send selected actions.
- Graph: `POST /planner/tasks` (delegated **Tasks.ReadWrite**) with `planId`, `bucketId`, `dueDateTime`, and `assignments` keyed by the owner's Entra user ID.
- **Owner matching:** the action owner "Priya" is matched to a person in the directory using people search (delegated **People.Read** / **User.ReadBasic.All**). The user confirms the match the first time; after that it's remembered alongside the voice and name.
- The task description includes the meeting, the date and the transcript quote the action came from.

### Follow-up email via Outlook
- Simplest option, which needs no permission: hand the drafted email to the Outlook app through the share sheet (already possible today).
- Richer option: **create a draft** in the user's mailbox addressed to the meeting attendees (Graph **Mail.ReadWrite**, `POST /me/messages`). The user reviews and sends it in Outlook. Clear Notes never sends email itself.

### Save notes for the record
- **OneDrive / SharePoint:** save the notes as a Word or Markdown document into a chosen folder, e.g. a project's "Meeting notes" folder (**Files.ReadWrite** or the narrower `Files.ReadWrite.AppFolder`).
- **OneNote:** create a page in a chosen notebook section (**Notes.Create**).
- Useful for governance minutes and project boards.

### Calendar awareness
- **On-device first:** iOS **EventKit** reads the calendars already on the phone, including Outlook accounts added to iOS. When you start recording during a calendar event, the meeting is titled automatically and its **attendee list** is used for speaker-naming suggestions and owner matching.
- Optional Graph **Calendars.Read** for richer attendee details (job titles, email addresses).

---

## Phase 2b: Teams meetings (still possible without a server)

For online Teams meetings, Microsoft already records a transcript **with speaker names**, which is better than anything a phone on the table can capture.

- **Import a Teams transcript:** pick a recent Teams meeting from your calendar. Clear Notes fetches its transcript and runs its own on-device notes, actions, topics and follow-ups on it. Speakers come pre-named from Teams, so no speaker separation is needed.
- Graph: `GET /me/onlineMeetings/{id}/transcripts/{id}/content` (WebVTT with speaker names). Delegated **OnlineMeetingTranscript.Read.All**.
- **Requirements and limits:**
  - The meeting must have transcription switched on in Teams.
  - The user must be the organiser or on the invite.
  - **OnlineMeetingTranscript.Read.All needs admin consent**, and your tenant admin controls whether Graph can access transcripts at all and whether speaker names are included.
- This is the most valuable Teams feature for the least effort, and it fits Clear Notes' "no bot" stance.

---

## Phase 3: a real Teams app (needs a back end)

A Teams app that lives inside meetings needs hosted components. Plan for a small, UK-hosted service (Azure UK South).

| Feature | What it needs |
|---|---|
| **Meeting side panel / tab** showing the meeting's notes and actions | A hosted web app (Teams tab) and a Teams app manifest |
| **Post the summary and actions to the meeting chat** as an Adaptive Card, with *Add to Planner* buttons | A bot registration (Azure Bot Service) and a back-end endpoint |
| **Automatic notes after every Teams meeting** (no manual import) | Graph **change notifications** for new transcripts, plus a service that receives them. Application permissions need an **application access policy**, or resource-specific consent (RSC) when the app is installed in a meeting |
| **Shared action tracking** across a team or meeting series | A small database for the shared state |

**Not recommended:** a bot that *joins* calls to record them (Teams real-time media). It needs heavyweight Windows-hosted media services, it's the "bot in the meeting" experience users dislike, and it adds the most risk for the least gain over Teams' own transcripts.

**Back-end essentials:** Azure UK South hosting, Entra-protected API, encryption at rest, audit logging, data minimisation (keep only notes and actions, never audio), penetration test, DSPT alignment, and **DTAC** if it's offered across the organisation.

---

## Other set-up worth doing

| Area | Why |
|---|---|
| **Mac app for online meetings** | A Mac version can capture the computer's **system audio** (ScreenCaptureKit), so it can take notes in Teams, Zoom or any other call without a bot, as Granola does. It reuses most of the iPhone code. |
| **Start recording faster** | App Intents and Shortcuts ("Start meeting notes"), a Control Centre or Lock Screen control, and a **Live Activity** showing the timer while recording. |
| **Ask your meetings** | On-device search across all meetings ("What did we agree about hosting?") using Apple Intelligence and on-device indexing, with no server. |
| **iCloud sync across your own devices** | iPhone ↔ iPad ↔ Mac via CloudKit's private database (encrypted, the user's own iCloud), with no Clear Notes server. Check this against NHS policy, since it's Apple's cloud. |
| **Intune / app protection** | If the app is used on NHS-managed phones: integrate the Intune App SDK (MAM policies such as blocking copy-paste to personal apps), and distribute as a **custom app through Apple Business Manager** rather than the public App Store. |
| **Templates per meeting type** | Board, project, 1:1, MDT-style huddle (non-clinical), with RAID-log (risks, actions, issues, decisions) outputs. |
| **Accessibility and languages** | VoiceOver review, Dynamic Type, and Welsh and other UK languages supported by Apple's on-device speech models. |
| **Telemetry (privacy-safe)** | Opt-in crash reporting only (TestFlight already provides crash logs). No content analytics. |

---

## Decisions (agreed 2 November 2026)

1. **Tenant: the local organisation tenant for the pilot, NHSmail later.** NHSmail tightly controls third-party apps and consent, so start its approval process well before moving over. Admin-consent permissions such as Teams transcripts take the longest. The app will read its tenant and client ID from build settings, so changing tenant needs no code changes.
2. **The app registration is owned by the infrastructure and cyber team**, and so is the Azure subscription later on (Phase 3). It isn't owned by a personal account.
3. **IG:** update the DPIA for each new data flow (To Do and Planner, email drafts, OneDrive, Teams transcripts) before it's used with real meetings. Voice memory already needs IG sign-off. The DPIA update is still to do.
4. **Distribution:** TestFlight for the pilot, then an Apple Business Manager custom app for wider rollout.

### What the infrastructure and cyber team will need

- **App registration** in the local tenant: single tenant, public client (mobile), with an **iOS/macOS platform** using the app's bundle ID. The redirect URI is `msauth.<bundle ID>://auth`.
- **Delegated permissions, added only as each feature is built:**

  | Feature | Permissions | Admin consent? |
  |---|---|---|
  | Sign-in | `User.Read` | No* |
  | To Do and Planner | `Tasks.ReadWrite` | No* |
  | Owner matching | `People.Read`, `User.ReadBasic.All` | No* |
  | Outlook draft | `Mail.ReadWrite` | No* |
  | OneDrive / OneNote | `Files.ReadWrite`, `Notes.Create` | No* |
  | Calendar details | `Calendars.Read` (optional) | No* |
  | Teams transcripts | `OnlineMeetings.Read`, `OnlineMeetingTranscript.Read.All` | **Yes** |

  \*Not required by Microsoft, but many organisations turn off user consent. If yours has, the team grants consent for everyone once.
- **Policy choices** for the team:
  - Conditional Access (e.g. MFA, compliant device).
  - Whether Intune app protection is required, which means adding the Intune App SDK.
  - Whether Graph can access Teams transcripts in this tenant.
- **For the builds:** the client ID and tenant ID go in GitHub Actions **variables**, like the bundle ID. They identify the app but aren't secrets, so no client secret is needed for the iPhone app.

## Suggested order

| Step | Scope | Server? |
|---|---|---|
| 0 | Infrastructure and cyber team creates the app registration; DPIA updated | No |
| 1 | Microsoft sign-in (MSAL + broker) | No |
| 2 | Send actions to To Do | No |
| 3 | Calendar awareness (EventKit) for titles and attendee-based naming | No |
| 4 | Send actions to Planner with owner matching | No |
| 5 | Outlook draft follow-up and save notes to OneDrive/OneNote | No |
| 6 | Import Teams transcripts (admin consent) | No |
| 7 | Mac app with system-audio capture | No |
| 8 | Teams app: side panel and meeting-chat summary card | **Yes** |
| 9 | Automatic post-meeting notes from Teams | **Yes** |

## References

- To Do API: [Create todoTask](https://learn.microsoft.com/graph/api/todotasklist-post-tasks?view=graph-rest-1.0), [To Do API overview](https://learn.microsoft.com/graph/api/resources/todo-overview?view=graph-rest-1.0)
- Planner API: [Create plannerTask](https://learn.microsoft.com/graph/api/planner-post-tasks?view=graph-rest-1.0), [Planner overview](https://learn.microsoft.com/graph/api/resources/planner-overview?view=graph-rest-1.0)
- Teams transcripts: [Get callTranscript](https://learn.microsoft.com/graph/api/calltranscript-get?view=graph-rest-1.0), [Meeting transcripts and recordings](https://learn.microsoft.com/microsoftteams/platform/graph-api/meeting-transcripts/overview-transcripts), [Transcript change notifications](https://learn.microsoft.com/graph/teams-changenotifications-callrecording-and-calltranscript)
- Sign-in: [MSAL for iOS and macOS](https://learn.microsoft.com/entra/msal/objc/), [SSO with the Authenticator broker](https://learn.microsoft.com/entra/msal/objc/single-sign-on-macos-ios)
- Permissions: [Microsoft Graph permissions overview](https://learn.microsoft.com/graph/permissions-overview)
