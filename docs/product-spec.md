# Clear-Notes — Product Spec (v0.1)

Clear-Notes is an AI meeting note taker that turns conversations into **traceable notes and tracked actions**. It takes the best features from the market (see [market-research.md](./market-research.md)) and adds a stronger focus on actions, traceability and UK data governance.

## Product principles

1. **No bot by default.** Capture from the device, so it works in Teams, Zoom, Meet and in-person meetings.
2. **The human stays in charge.** AI suggests notes and actions. A person reviews them before anything leaves the app.
3. **Every claim is traceable.** Each summary line and action links to the transcript timestamp that supports it.
4. **Actions outlive meetings.** Actions persist across a meeting series until they are closed.
5. **Privacy by design.** UK/EU hosting, a configurable audio-retention policy (default: delete after transcription), and an audit log.

## Core user flow

```
Calendar event ──► Start capture (desktop/mobile/upload)
                     │
                     ▼
            Live transcript + user's own notes
                     │  meeting ends
                     ▼
     AI enhancement (template-driven)
       • Summary • Decisions • Risks • Open questions
       • Actions {owner, due, confidence, source timestamp}
                     │
                     ▼
        Review screen: accept / edit / reject
                     │
         ┌───────────┼──────────────┬──────────────┐
         ▼           ▼              ▼              ▼
   Action register  Task tools   Follow-up      Searchable
   (carry-over)     (Planner,    email draft    knowledge base
                    Jira, …)                    + MCP for agents
```

## MVP scope (Phase 1)

| # | Feature | Notes |
|---|---|---|
| 1 | Upload or record audio (browser mic + tab audio) | Web app first; desktop app comes later |
| 2 | Transcription with speaker diarisation | Pluggable engine: cloud API or local Whisper |
| 3 | Notes editor alongside the transcript | Markdown; user notes guide the AI's emphasis |
| 4 | Templates | General, 1:1, Project/RAID, Board/Governance, Stand-up |
| 5 | AI enhancement with citations | Uses the Claude API with structured (JSON) output |
| 6 | Action review and register | Owner, due date, status; carries over across a series |
| 7 | Export | Markdown, .docx, copy-to-email follow-up |
| 8 | Search across meetings | Keyword search first; semantic search in Phase 2 |

### Phase 2
- Desktop capture app (system audio, bot-free) with calendar integration (Microsoft 365 / Google)
- Push actions to Microsoft Planner / To Do, Jira and Asana
- "Ask across meetings" chat (RAG over transcripts)
- MCP server: `list_meetings`, `get_meeting`, `search_meetings`, `list_actions`, `update_action`
- Speaker naming matched to calendar attendees; custom vocabulary

### Phase 3
- Live assist: surface open actions from the last meeting in the series; flag decisions that have no owner
- Teams integration (pull transcripts via Microsoft Graph when available)
- Organisation admin: SSO, retention policies, audit log export, redaction rules

## Data model (initial)

```
Meeting      { id, title, series_id?, started_at, ended_at, attendees[], template_id, audio_ref?, status }
Transcript   { meeting_id, segments[{ start_ms, end_ms, speaker, text }] }
Note         { meeting_id, user_markdown, enhanced_markdown, citations[{ claim_id, segment_ids[] }] }
Action       { id, meeting_id, series_id?, text, owner, due_date?, status(open|done|dropped),
               confidence, source_segment_ids[], external_ref? }
Template     { id, name, sections[{ key, title, instructions }] }
```

## AI design

- **Model:** Claude (latest Sonnet-class model for enhancement; a Haiku-class model for cheap tasks such as titling and classification).
- **Structured output:** the enhancement call returns JSON that matches the template sections plus an `actions[]` array. Every item carries `source_segment_ids`.
- **Grounding rule:** the prompt tells the model to output only claims it can cite. If it can't cite a claim, it leaves it out.
- **Long meetings:** chunk the transcript, summarise each chunk, then merge (map-reduce). Use prompt caching for the template and system prompt.
- **Action quality:** each action needs a verb-first description, an owner (or "Unassigned"), a due date only when one was stated, and a confidence of low, medium or high.

## Suggested tech stack

| Layer | Choice | Why |
|---|---|---|
| Frontend | Next.js (React, TypeScript) | One codebase for the web app; easy path to a desktop app with Tauri/Electron later |
| Backend | Next.js API routes → separate service later | Fast to start |
| DB | PostgreSQL (+ pgvector in Phase 2) | Relational actions + semantic search |
| Transcription | Pluggable: Azure AI Speech (UK South) / Deepgram / local Whisper | Data residency options |
| LLM | Anthropic Claude API | Structured output, long context |
| Auth | Microsoft Entra ID (OIDC) | Fits M365 organisations |
| Hosting | UK region (Azure UK South / AWS eu-west-2) | Data residency |

## Governance checklist (before using with real meetings)

- [ ] DPIA completed with your Information Governance team
- [ ] Consent/transparency notice shown when recording starts
- [ ] Audio retention: delete after transcription by default
- [ ] Supplier terms for the LLM and transcription vendors: no training on customer data, UK/EU processing
- [ ] Non-clinical use only until a DCB0129/0160 clinical safety case exists
- [ ] Do not process real personal or sensitive data during development; use synthetic test meetings

## Success metrics

- At least 80% of AI-suggested actions accepted without major edits
- Time from meeting end to shared notes: under 5 minutes
- At least 70% of actions closed by the next meeting in the series
