# Clear Notes — Roadmap (Phase 2 onwards)

_Planning notes, not yet built. Last updated 5 November 2026 (meeting file sharing proposed; web app upload added as a future requirement)._

Phase 1 (done) is a private, on-device iPhone app: capture, transcription, speakers, notes, actions, playback and voice memory. Next we connect it to where work actually happens, mainly Microsoft 365, while keeping the privacy-first design.

## Guiding principles

1. **No server unless it's needed.** Most Microsoft 365 features can be called straight from the iPhone with the user's own sign-in (delegated permissions). A back end is only needed for things that must run when the phone isn't involved, such as a Teams bot or a team-wide service.
2. **Least privilege.** Ask only for the permissions a feature needs, and only when the user turns that feature on.
3. **The user sends things out.** Nothing is pushed to Microsoft 365 automatically. The user reviews and taps *Send to Planner* or *Send to To Do*.
4. **Governance first.** Each integration changes the data flow, so the DPIA needs updating and Information Governance (IG) needs to approve it before use with real meetings.
5. **General-purpose, not NHS-specific.** NHSmail and the local trust tenant are the first places it will be used, not the product's limits. Every feature has to work for any organisation, and for someone with no work account at all:
   - Microsoft 365 features work with **any Entra ID tenant**. The tenant and client ID are configuration, not code. There's no NHS-specific logic, wording or defaults.
   - Organisation controls such as Intune app protection, Conditional Access and admin consent are **switched on by the organisation's own policy**. They aren't hard-coded, and the app behaves normally when they're absent.
   - Sign-in stays **optional**. Without it, everything on the device keeps working, including recording, notes, minutes, sharing and the share sheet.

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
- Simplest option, which needs no permission: hand the drafted email to the Outlook app through the share sheet. **This doesn't work under NHSmail's Intune app protection:** Outlook won't accept shared or pasted content from Clear Notes. See *On hold: sharing into NHSmail Microsoft 365* below.
- Richer option: **create a draft** in the user's mailbox addressed to the meeting attendees (Graph **Mail.ReadWrite**, `POST /me/messages`). The user reviews and sends it in Outlook. Clear Notes never sends email itself.

### Save notes for the record
- **OneDrive / SharePoint:** save the notes as a Word or Markdown document into a chosen folder, e.g. a project's "Meeting notes" folder (**Files.ReadWrite** or the narrower `Files.ReadWrite.AppFolder`).
- **OneNote:** create a page in a chosen notebook section (**Notes.Create**).
- Useful for governance minutes and project boards.

### Calendar awareness (built: Settings → Calendar)
- **On-device first:** iOS **EventKit** reads the calendars in Apple's Calendar app, after the user allows it. When you start recording during an event, the meeting is titled automatically. Where an attendee list is available, it feeds speaker-naming suggestions and owner matching.
- **Outlook app calendars** are private to the Outlook app. They reach EventKit in one of two ways:
  - **Outlook → Settings → your account → Sync Calendars.** This copies events to Apple's Calendar app. Expect titles and times, but probably not attendees, because iOS doesn't let apps like Outlook write attendee lists. An Intune app protection policy can block it ("Sync policy managed app data with native apps or add-ins").
  - **Adding the work account in iOS Settings** gives full events with attendees, but many organisations block the built-in iOS mail and calendar apps through Conditional Access.
- **Calendars shared with you** (a colleague's or a team calendar) usually don't sync through a work account added in iOS Settings, because Exchange ActiveSync doesn't support shared or delegate access. In testing, NHSmail did sync many colleagues' shared calendars to the phone (hidden in Apple's Calendar app but visible to apps). So Clear Notes uses only the main calendar by default, and *Choose calendars* (built) turns others on. Graph `Calendars.Read.Shared` can read them after sign-in. When it's added, let the user choose which calendars count, so a colleague's meetings don't show as "Up next".
- **Microsoft Graph** `Calendars.Read`, after Microsoft sign-in, is the dependable route for work calendars. It gives full attendee details and the Teams join link that transcript import needs, and it works whatever the Outlook settings are.

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

## Proposed next: share a meeting as a Clear Notes file (no server)

_Proposed 5 November 2026, waiting for the go-ahead._

- **Share → Share meeting as a Clear Notes file** makes one `.clearnotes` file to send by AirDrop, Messages or Mail. Anyone with Clear Notes taps it, chooses **Open in Clear Notes**, previews it and imports their own editable copy. Re-importing the same meeting offers **Update** or **Keep both**.
- **Contents:**
  - Always: title, date, duration and invited people; the transcript with speaker names; summary, topics and decisions; actions (owner, due date, status); minutes.
  - Off by default: the sender's private notes, and the recording (about 230 MB for two hours).
  - Never: remembered voiceprints, which are biometric data.
- **Optional password:** AES-256-GCM with a key derived from the password, so a misdirected email can't be read.
- **Without the app,** the minutes can go along as readable text.
- NHSmail's Outlook, OneDrive and Teams will refuse the file while Clear Notes isn't Intune-managed (see *On hold* below).
- **The file format is designed to be the upload format for the web app below:** a versioned, documented JSON schema (`formatVersion`, stable meeting and action IDs) in `docs/`. The app, the web app and any future import all read the same thing.

## Future: a Clear Notes web app (upload meetings), governance permitting

_Added 5 November 2026 as a future requirement. Not planned in detail until governance agrees._

**What it's for**
- Upload a meeting from the iPhone to a web app.
- Read, search and edit notes and minutes on a PC.
- Export to Word.
- Keep a team or meeting-series archive.
- Track actions across meetings.
- It could share a back end with the Phase 3 Teams app.

**How it would work**
- **The user chooses each upload:** "Upload to <organisation> Clear Notes". It shows exactly what will be sent, and the user can delete it from the server. Automatic upload stays off unless the organisation turns it on.
- **It uses the same file format as meeting sharing.** Uploads are the transcript, notes, actions and minutes. Audio and voiceprints are never uploaded by default; audio only if governance explicitly allows it.
- **Sign-in uses Microsoft Entra ID** with the same app registration (single tenant per organisation, or multi-tenant for general release). Access is by role: owner, attendees, team.

**Hosting and governance (needs a server)**
- Hosted in the organisation's own cloud, e.g. Azure UK South in the subscription the infrastructure and cyber team owns, with UK data residency.
- Encryption in transit and at rest, audit logging, and set retention and deletion periods.
- DPIA update, DSPT alignment, DTAC if offered across the organisation, and a penetration test.

**General-purpose (principle 5)**
- Any organisation can host its own instance.
- Nothing NHS-specific is built in. NHS-specific governance stays in documents like this one.

**Open questions for later**
- Who hosts it?
- What's uploaded: the full transcript, or only the notes and minutes?
- How long is it kept?
- Who can see a meeting: the owner, the attendees or the team?
- Should audio ever be allowed?

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
  | Calendars shared with you | `Calendars.Read.Shared` (optional) | No* |
  | Teams transcripts | `OnlineMeetings.Read`, `OnlineMeetingTranscript.Read.All` | **Yes** |

  \*Not required by Microsoft, but many organisations turn off user consent. If yours has, the team grants consent for everyone once.
- **Policy choices** for the team:
  - Conditional Access (e.g. MFA, compliant device).
  - Whether Intune app protection is required, which means adding the Intune App SDK.
  - Whether Graph can access Teams transcripts in this tenant.
- **For the builds:** the client ID and tenant ID go in GitHub Actions **variables**, like the bundle ID. They identify the app but aren't secrets, so no client secret is needed for the iPhone app.

## On hold: sharing into NHSmail Microsoft 365

_Recorded 3 November 2026. **Waiting on the NHSmail administrator.** Nothing is built yet._

### The problem
Minutes and notes can't be copied, pasted or shared from Clear Notes into Outlook, OneDrive or Teams on the iPhone. NHSmail's central Intune **app protection policy** covers those apps. Microsoft's documentation describes these settings:
- **Restrict cut, copy and paste: Policy managed apps** blocks pasting from an unmanaged app into a managed one.
- **Receive data from other apps: Policy managed apps** blocks sharing into managed apps.

Clear Notes isn't a policy-managed app, so both are refused. This is deliberate data-loss protection. **Don't get round it** with personal email, AirDrop to a personal device or screenshots, because that would breach the policy and IG rules.

### The gate
**Can a custom app be added to NHSmail's Intune app protection policy?** Kev is asking the NHSmail administrator. NHSmail's Intune is run centrally by NHS England, so expect a formal onboarding and assurance process (likely DTAC, DSPT, the DPIA and possibly a penetration test). If the answer is no, options 2 and 3 aren't worth building for NHSmail.

### Options

1. **Apple Mail with the NHSmail account already on the iPhone (no code).** The account added in iOS Settings for the calendar may also allow Mail: Settings → Apps → Mail → Mail Accounts. If it does, in Clear Notes tap Share → Mail and send the minutes from the NHSmail address. Apple Mail isn't covered by app protection. Confirm with IG that it's acceptable. A possible small follow-up is an **Email minutes** button that fills in the subject and attaches the minutes as a Word or PDF file.

2. **Make Clear Notes an Intune-managed app.** Add MSAL sign-in and the **Intune App SDK** (SwiftPM or framework; iOS 16 or later is required, and we target 17). Call `registerAndEnrollAccountId` after sign-in, and support App Protection CA (`protapp` client capability, `remediateComplianceForIdentity`). MSAL interactive sign-in should use WKWebView.
   - **Result:** copy, paste and share into Outlook, OneDrive and Teams work normally. Clear Notes' own data also gets org protections (encryption, PIN, selective wipe), which helps the DPIA.
   - **The policy must be NHSmail's.** Intune keeps each organisation's data separate, so managing Clear Notes from the local tenant won't open up NHSmail Outlook.
   - The admin adds the app by bundle ID ("more apps") to the policy's targeted apps.
   - Docs: [Intune App SDK for iOS](https://learn.microsoft.com/intune/developer/app-sdk/ios-phase-1), [iOS app protection settings](https://learn.microsoft.com/intune/app-management/protection/ref-settings-ios).

3. **Send straight into Microsoft 365 with Microsoft Graph.** Create an Outlook draft (`Mail.ReadWrite`), save minutes as a Word document to OneDrive or SharePoint (`Files.ReadWrite`), or post to a Teams chat. This skips the phone's clipboard, but it still needs tenant consent, and NHSmail's Conditional Access may also require option 2. It's the same NHSmail approval. **For the local-tenant pilot**, the infrastructure and cyber team can approve it themselves, which is useful if the trust has its own Teams, SharePoint or OneDrive there. Content leaves the iPhone, so the DPIA needs updating.

### Whatever is built stays general (see principle 5)
- **Intune App SDK:** it only takes effect when a signed-in account's organisation targets the app with an app protection policy. For everyone else, including unmanaged users, App Store installs and other Microsoft 365 tenants, the app behaves exactly as now. Never set `MAMPolicyRequired`, which would block the app without a policy (Apple won't accept that on the App Store either). Support multi-identity if a personal or second account is ever allowed.
- **Microsoft Graph sharing** (Outlook draft, OneDrive, Teams) works with any tenant: a multi-tenant app registration for general release, or a single-tenant one per organisation, set through build or app configuration. NHSmail is one deployment.
- **Apple Mail / share sheet / Email minutes** works for anyone, with any mail account.
- Keep NHS-specific guidance (NHSmail onboarding, DTAC, DSPT) in docs like this one, not in the app.

### Plan once the gate is answered
- **NHSmail says yes:** build options 2 and 3 together, prove them against the local tenant with the infrastructure and cyber team, then submit to NHSmail onboarding with that evidence.
- **NHSmail says no:** rely on option 1, if IG agrees, and option 3 for the local tenant only.
- **Open questions:** Can Mail be turned on for the NHSmail account on the iPhone? Does the local tenant have its own Teams, SharePoint or OneDrive, or is everything on NHSmail?

## Suggested order

| Step | Scope | Server? |
|---|---|---|
| 0 | Infrastructure and cyber team creates the app registration; DPIA updated | No |
| 1 | Microsoft sign-in (MSAL + broker) | No |
| 2 | Send actions to To Do | No |
| 3 | Calendar awareness (EventKit) for titles and attendee-based naming. **Built**: see Settings → Calendar | No |
| 4 | Send actions to Planner with owner matching | No |
| 5 | Outlook draft follow-up and save notes to OneDrive/OneNote | No |
| 6 | Import Teams transcripts (admin consent) | No |
| 7 | Mac app with system-audio capture | No |
| 8 | Teams app: side panel and meeting-chat summary card | **Yes** |
| 9 | Automatic post-meeting notes from Teams | **Yes** |
| 10 | Web app: upload meetings for reading, search and editing on a PC (governance permitting; same file format as meeting sharing) | **Yes** |

## References

- To Do API: [Create todoTask](https://learn.microsoft.com/graph/api/todotasklist-post-tasks?view=graph-rest-1.0), [To Do API overview](https://learn.microsoft.com/graph/api/resources/todo-overview?view=graph-rest-1.0)
- Planner API: [Create plannerTask](https://learn.microsoft.com/graph/api/planner-post-tasks?view=graph-rest-1.0), [Planner overview](https://learn.microsoft.com/graph/api/resources/planner-overview?view=graph-rest-1.0)
- Teams transcripts: [Get callTranscript](https://learn.microsoft.com/graph/api/calltranscript-get?view=graph-rest-1.0), [Meeting transcripts and recordings](https://learn.microsoft.com/microsoftteams/platform/graph-api/meeting-transcripts/overview-transcripts), [Transcript change notifications](https://learn.microsoft.com/graph/teams-changenotifications-callrecording-and-calltranscript)
- Sign-in: [MSAL for iOS and macOS](https://learn.microsoft.com/entra/msal/objc/), [SSO with the Authenticator broker](https://learn.microsoft.com/entra/msal/objc/single-sign-on-macos-ios)
- Permissions: [Microsoft Graph permissions overview](https://learn.microsoft.com/graph/permissions-overview)
