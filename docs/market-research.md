# AI Meeting Note Takers — Market Research

_Last updated: 30 October 2026_

This is a review of the main AI meeting note takers. It looks at what each one does well, where each falls short, and which features Clear-Notes should borrow or improve on.

> Note on sources: most comparison articles are affiliate or vendor-adjacent. Treat prices and feature claims as indicative and check them on vendor sites before relying on them.

## 1. The landscape at a glance

| Product | Capture model | Standout strengths | Weaknesses | Indicative price |
|---|---|---|---|---|
| **Granola** | Bot-free (device audio) | Hybrid notes: your rough notes plus the transcript become "enhanced" notes. Templates ("Recipes"). Unobtrusive. | Limited speaker identification. Templates can be verbose. Desktop-centric. | Free tier; ~$14/user/mo Business |
| **Otter.ai** | Bot joins call + mobile/in-person | Real-time shared transcript, live collaboration, speaker ID, in-person capture via phone | Best features behind higher tiers; bot visibility | ~$8–20/user/mo |
| **Fireflies.ai** | Bot joins call | Deep integrations (CRM, Slack, task tools), conversation intelligence, MCP server for AI agents, "Live Assist" during calls | Sales-oriented; bot visibility; cloud-only | Free tier; paid per user |
| **Fathom** | Bot joins call | Generous free tier (unlimited recording/transcription), fast summaries, official MCP/API | All processing in vendor cloud; advanced AI on paid tiers | Free; ~$15/user/mo Team |
| **Microsoft Teams Copilot / Intelligent Recap** | Native to Teams | No extra bot; recap with decisions + action items; links to Planner/To Do; recap option without saving a transcript | Licence-dependent (Copilot / Teams Premium); Teams-only; limited customisation | Bundled with M365 add-ons |
| **Jamie / similar** | Bot-free (device audio) | Privacy-first, local capture, works across any platform | Smaller ecosystems | Varies |
| **Fellow ("Ask Fellow")** | Bot + agenda tooling | Agenda → notes → actions workflow; AI agent across meeting history | Strongest when the whole team adopts it | Per user |

## 2. Key trends (2025–2026)

1. **Bot-free capture is winning on user experience.** Granola and Jamie record system and mic audio locally, so no "Notetaker has joined" participant appears. This lowers social friction and works with any meeting platform, including in-person meetings.
2. **"Hybrid" notes beat pure transcripts.** The most-loved pattern is: the user jots a few key points, and AI expands them using the transcript. The user stays in control of what matters.
3. **Templates per meeting type.** 1:1s, stand-ups, project boards, clinical MDTs and interviews each need a different structure (decisions, risks, actions, open questions).
4. **From notes to actions to agents.** Leaders now expose meeting data through MCP servers and APIs, so AI agents (Claude, ChatGPT, Copilot) can query meeting history and create tasks, tickets and follow-up emails.
5. **"Ask across all meetings".** Chat or search over the whole meeting history ("What did we agree with the estates team about X?").
6. **Live assist.** In-meeting prompts, such as reminders of open actions from the last meeting, or nudges when a decision has no owner.
7. **Privacy and governance as a differentiator.** Data residency, local processing, retention controls, consent banners and audit trails are now buying criteria, especially in regulated sectors.

## 3. Feature inventory (best of market)

### Capture
- Bot-free desktop capture (system + mic audio) — *Granola, Jamie*
- Optional bot for scheduled online calls — *Otter, Fireflies, Fathom*
- Mobile / in-person recording — *Otter*
- Upload existing recordings (audio/video files)
- Calendar integration to auto-detect meetings and attendees

### Transcription
- Real-time streaming transcript
- Speaker diarisation and naming (matched to calendar attendees)
- Custom vocabulary (acronyms, names, organisation jargon)
- Multi-language support

### AI notes
- Hybrid "enhanced notes" that merge user notes with the transcript — *Granola*
- Meeting-type templates (custom, shareable) — *Granola Recipes*
- Summary, decisions, risks, open questions, key quotes
- Citations: every AI statement links back to the transcript timestamp

### Actions
- Action extraction with **owner, due date, and confidence**
- Human review step: accept / edit / reject each action before it is pushed anywhere
- Push to task tools (Planner, To Do, Jira, Asana, Trello, Linear)
- Draft follow-up email or message to attendees
- Track actions across meetings (carried-over or overdue items surface in the next meeting)

### Knowledge and agents
- Search and chat across all meetings
- MCP server / API so external AI agents can read meetings and write actions
- Webhooks on "meeting processed"

### Governance
- Consent notice and recording indicator
- Retention policies (auto-delete audio after transcription)
- Data residency (UK/EU hosting), encryption at rest and in transit
- Role-based sharing; redaction of sensitive data
- Audit log

## 4. Gaps and opportunities for Clear-Notes

| Gap in market | Opportunity |
|---|---|
| Action items are extracted but rarely **validated** or **tracked** across meetings | Make actions a first-class object: an action register that persists across a meeting series, with "carried over" and "overdue" states |
| AI summaries lack **traceability** | Every summary line and action links to the transcript snippet that supports it |
| Bot-free tools are weak on **speaker ID** | Combine calendar attendees + diarisation + one-click speaker naming |
| Most tools are **US-cloud** | UK/EU hosting option, "process and discard audio" mode, and optional local transcription (e.g. Whisper) |
| Templates are generic | Templates for public-sector and healthcare meetings (board/governance, project, 1:1, MDT-style huddles) with RAID-log outputs (Risks, Actions, Issues, Decisions) |
| Agents need structured access | Ship an MCP server from day one: `list_meetings`, `get_meeting`, `search`, `list_actions`, `update_action` |

## 5. Regulatory and governance notes (UK / NHS context)

If Clear-Notes is used in NHS or other health and care settings:

- **NHS England guidance on AI-enabled ambient scribing products** sets expectations on clinical safety, information governance, data protection and transparency for ambient voice technology (AVT). It was updated in April 2026.
- **The NHS England AVT Supplier Registry** (January 2026) lists suppliers that have self-certified against national standards.
- **MHRA and NHS England published a joint position (July 2026) on medical-device regulation for AVT.** A tool used only for *administrative* meetings, rather than clinical consultations, is very unlikely to be a medical device. Generating clinical documentation changes this, so get advice before scoping in clinical use.
- Expect to need a **DPIA**, **DTAC** assessment, **DSPT** alignment, a **DCB0129/0160** clinical safety case for clinical use, and clear consent and transparency notices.
- **Microsoft Teams Copilot / Intelligent Recap** may already be available to some organisations through M365 licensing. Clear-Notes should integrate with Teams, not just compete with it.

Recommendation: target **non-clinical meetings** (project, governance, operational, 1:1) for the MVP. This avoids medical-device scope while the product matures.

## Sources

- [TechRepublic — 6 Best AI Meeting Note Takers for 2026](https://www.techrepublic.com/article/news-best-ai-meeting-note-takers-2026/)
- [Tana — Best Otter alternatives 2026](https://tana.inc/blog/best-otter-alternatives-2026)
- [Tana — Best AI meeting assistants 2026](https://tana.inc/blog/best-ai-meeting-assistants-2026)
- [Simular — Hands-on review of 8 tools](https://simular.ai/alternatives/ai-meeting-note-takers)
- [Zack Proser — Best AI Meeting Notes 2026](https://zackproser.com/blog/best-ai-meeting-notes-2026)
- [Skillscouter — Granola review 2026](https://skillscouter.com/granola-review/)
- [Granola llms.txt](https://granola.ai/llms.txt)
- [meetingnotes.com — Note takers with MCP and agent integration](https://meetingnotes.com/blog/ai-meeting-notes-with-mcp-and-ai-agent-integration)
- [Fireflies MCP server beta](https://devcuration.substack.com/p/firefliesai-mcp-server-beta-launch)
- [Microsoft — Latest updates in Copilot for Teams](https://support.microsoft.com/en-US/Office/latest-updates-in-copilot-for-teams)
- [Nexacu — Copilot in Teams: summaries, recaps and action items](https://nexacu.com.au/insights-blog/copilot-in-microsoft-teams-meeting-summaries-recaps-action-items)
- [NHS England — Guidance on AI-enabled ambient scribing products](https://www.england.nhs.uk/long-read/guidance-on-the-use-of-ai-enabled-ambient-scribing-products-in-health-and-care-settings)
- [NHS England — Medical device regulation for AVT products](https://www.england.nhs.uk/long-read/medical-device-regulation-for-ambient-voice-technology-products/)
- [Digital Health — NHSE publishes fresh guidance on ambient scribes (Apr 2026)](https://www.digitalhealth.net/2026/04/nhse-publishes-fresh-guidance-on-safe-use-of-ambient-scribes/)
