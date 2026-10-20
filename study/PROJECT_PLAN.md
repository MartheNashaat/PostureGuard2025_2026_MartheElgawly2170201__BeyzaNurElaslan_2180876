# PostureGuard — Full Project Plan (annotated)

Priority ordering across pre-study validation, app engineering, backend, study
design, and the paper. Annotated 15 September 2026; brought in line with the
code on `main` on 15 October 2026; study design changed on 15 October 2026
(see *Decisions of 15 October* below).

The original plan text is preserved; each task carries a status and a short
note on what was built or what changed.

## Where the project stands

- **Done** — Section 1 in full (device benchmarks, telemetry integrity checks,
  onboarding / consent form), frame-rate throttling, and the A/B feedback
  variants. Results in `study/results/SECTION1_RESULTS.md`.
- **Decided** — each participant **chooses one feedback version (A or B) in
  the app and uses only that one**. The counterbalanced crossover is dropped.
  See Section 4.
- **Agreed** — the session upload payload, in `study/API_SCHEMA.md`. The
  per-second 0–100 score is not needed (16 October 2026).
- **In progress** — the study server in `backend/` (FastAPI + PostgreSQL):
  `POST /api/sessions` works and is tested; HTTPS deployment is next.
- **Participant IDs** — chosen by the participant (6+ letters/numbers,
  case-sensitive), in both the app and the onboarding form. The earlier
  `PG-XXXX-XXXX` generated IDs are gone.
- **Done** — Version C (both) is hidden from participants for now.
- **Done** — sessions whose only defect is gaps are uploaded with the gap
  count; only seriously broken sessions are blocked. Crash recovery added.
  See Section 1.

### Decisions of 15 October 2026

| # | Decision | What changes | Who |
|---|---|---|---|
| 1 | **Gap-only sessions are uploaded.** Clean sessions are uploaded as before (`is_valid = true`). A session whose only problem is gaps (a few seconds missing because Android throttled the app) is sent with `integrity.is_valid = false` and its `gap_count`. Sessions with out-of-order or duplicate timestamps, missing timestamps, a summary that disagrees with its events, or no events at all stay blocked. | App: the gate/upload rule changes from "block on any issue" to "block unless `hasOnlyGaps`". Server: must accept `is_valid = false`. `study/API_SCHEMA.md` updated. | Marthe (app), Beyza (server) |
| 2 | **Version C (both) is hidden** from participants for now. Only A and B can be selected. | App: hide the C button. | Marthe |
| 3 | **Each participant chooses one version and uses only that one.** No assigned order, no second phase, no washout. The participant picks A (Dimming) or B (Baseline) with the buttons on the app's home screen. | Form, Apps Script and `study/README.md`: remove the AB/BA order assignment, the phase and washout text, and the order shown on the confirmation screen. Consent text must describe the new design. **Done (form, Apps Script, README).** | Beyza |
| 4 | **No ethics committee approval is needed** for now. The form says the study is carried out with the approval of the project supervisor. | Ethics placeholders and the ethics-approval steps removed from the form, `study/README.md` and this plan. **Done.** | Beyza |

Decisions 3 and 4 are done in the form, Apps Script and `study/README.md`.
Decisions 1 and 2 are done in the app (20 October 2026). Decision 1 goes
slightly further than written: see Section 1.

| Status | Meaning |
|---|---|
| ✅ **DONE** | Built and tested |
| 📌 **DECIDED** | Settled, nothing to build |
| ⚠️ **UPDATE** | Written, but now needs revising |
| 🔶 **IN PROGRESS** | Started, not finished |
| ⬜ **OPEN** | Not started |

---

## 1 — Pre-Study Technical Validation

*Difficulty: Easy–Medium*

✅ **DONE** · Run continuous device stress tests (30 min / 60 min sessions) on
the Android device. — *Marthe*

✅ **DONE** · Measure CPU usage, battery consumption (%/hr), and device
temperature profiles across different frame rates — this data feeds directly
into the benchmarks needed for the paper. — *Marthe*

> A 7-rate sweep (1–30 FPS) chose 3 FPS: 38% less CPU than unthrottled and
> 2.5 °C cooler. Then five 30/60-min real-use runs (PiP open/closed, with and
> without other apps). The app records battery, temperature, CPU and thermal
> status every 15 s during every session (`device_metrics` table), so the same
> data will arrive per participant. Full results, limitations and draft paper
> text: `study/results/SECTION1_RESULTS.md`.

✅ **DONE** · Build automated telemetry integrity checks: confirm no missing
timestamps and that the timestep sequence is continuous before trusting any
uploaded session. — *Beyza*

> Built as `TelemetryIntegrityService` (pure, no database) plus
> `TelemetryIntegrityGate` (reads SQLite, blocks the upload). Detects gaps,
> missing or unreadable timestamps, backward clock jumps, duplicate
> timestamps, and summary rows that disagree with their own events. Returns
> `{isValid, issues, gapCount, missingCount}`. 25 unit tests pass; nothing is
> ever auto-deleted.
>
> Worth knowing: the persisted log rate is **1 Hz**, not 2–5 FPS. The 2–5 FPS
> figure is the ML Kit inference rate, and those results are never written to
> the database.
>
> ✅ **Decision 1 (15 Oct), done 20 Oct:** sessions whose only problem is
> gaps are uploaded with `is_valid = false` and their `gap_count`. Long gaps
> also leave fewer samples than the span implies, so a `sampleCountMismatch`
> that comes *with* gaps is accepted too (`report.hasOnlyGapEffects`);
> `gap_count` is always > 0 for these, which the server already requires.
> Everything else stays blocked. Not yet tested against a real server.
>
> ✅ **Recording fixes (20 Oct)**, so the other checks don't block real
> sessions:
>
> - Event timestamps come from a monotonic stopwatch anchored to the wall
>   clock once, and are kept strictly increasing — no backward jumps or
>   duplicates from clock syncs or timer bursts.
> - The first event is logged at session start, so no session is empty.
> - Pending inserts finish before the summary is computed, and the summary's
>   end time is the last event's — no duration or end-time mismatch.
> - **Crash recovery:** a session cut off by a crash or force-stop is
>   finished from its saved events on the next app start and queued.
>   Tested on the phone 20 Oct (force-stop → 44 s session recovered).
> - Blocked sessions are re-checked on every app start, so ones blocked by
>   older rules get uploaded if they now pass.

✅ **DONE** · Prepare user onboarding / consent forms (Google Form or a simple
web form) linked to each participant's unique user ID. — *Beyza*

> **Decisions 3 and 4 (15 Oct), done:** the AB/BA order, phases and washout
> are gone; participants are told to choose A or B in the app and keep it. The
> ethics committee sentence is replaced by "carried out with the approval of
> the project supervisor".
>
> Self-contained HTML form — a Google Form cannot check a chosen ID against
> earlier submissions and ask for another. Covers study
> description, granular informed consent, the Section 4 demographics, and the
> participant's **own choice of ID**, checked against the app's rule (6+
> letters/numbers, case-sensitive). The backend refuses an ID that is already
> taken (ignoring case), and the form refuses one containing the participant's
> name or email. Submissions go to Google Sheets via Apps Script until the
> real backend exists. Files in `study/`.

---

## 2 — App Engineering & Optimization

*Difficulty: Medium*

✅ **DONE** · Implement frame-rate throttling — sample at roughly 2–5 FPS
instead of 30 FPS to prevent thermal throttling and battery drain. — *Marthe*

> 3 FPS while in picture-in-picture, 15 FPS when full-screen (3 FPS made the
> skeleton look laggy). Head-position smoothing was made time-based so it
> behaves the same at any rate.

> Affects the ML Kit inference rate only. Database logging is already a fixed
> 1 Hz timer and is unaffected. If that ever changes, the integrity checker's
> expected interval must change with it.

✅ **DONE** · Build the two feedback variants explicitly: **Version A —
Dimming only** vs. **Version B — Baseline overlay**. Same underlying logging
and detection logic in both. — *Marthe*

> One APK. Three buttons on the home screen choose the feedback: **A —
> Dimming** (sun icon), **B — Baseline** (person icon), **C — Both**. A dims
> the screen and shows no baseline drawing; B shows the baseline drawing and
> does not dim; C does both. Voice alerts, vibration and the coloured border
> stay in all three. Each session stores its variant. A and B checked on the
> phone 20 Oct.
>
> ✅ **Decision 2 (15 Oct), done 20 Oct:** the C button is hidden; only A
> and B can be selected. C still works in code and on the server. A phone
> that already had C selected keeps running C.
>
> **Decision 3 (15 Oct):** the participant's own choice on the home screen
> *is* the study design — no order is assigned and nobody switches versions.
> The app still lets a participant change their choice at any time, so
> instruct participants to stay on the version they chose, and check at
> analysis that each `user_id` has a single `variant`. Locking the choice
> after the first session is a possible later improvement, not decided.

✅ **DONE** · Add local SQLite/queue caching so a network drop during a session
doesn't lose timestep data — queue and retry once connectivity returns.
— *Marthe*

> `upload_queue` table: each finished session is queued, then sent; failures
> stay `pending` and retry after the next session, on app start, and when the
> home screen opens. A `422` from the server marks the session `blocked`
> (resending can't succeed) and is not retried. The integrity check runs before sending, as below;
> failing sessions are marked `blocked` and kept on the phone.

> Run the integrity check before the queue flushes, not after, so a corrupted
> session is caught on the device.

---

## 3 — Backend & Cloud Deployment

*Difficulty: Medium–Hard*

✅ **DONE** · Define the exact JSON schema / API payload before writing
endpoints (fields: `user_id`, `session_id`, `timestamp`, `score`, `zone`,
`streak`, `battery`, `temperature`, `app_version`). — *Beyza*

> Agreed: `study/API_SCHEMA.md`. The per-second 0–100 score is **not needed**
> (16 October 2026) — the zone per second and the session's
> `good_posture_percent` are enough.
>
> `variant` is in the proposal and the app already sends it. Participants
> can only select `A` or `B` (C hidden, Decision 2). Each participant chooses
> one version (Decision 3), so `variant` is what puts a participant's
> sessions in the A or B group — the comparison the study is about.
>
> Decision 1 is reflected in the schema: `integrity.is_valid` can be `false`
> for gap-only sessions, and the server must accept them.

🔶 **IN PROGRESS** · Build the Web API (e.g. FastAPI or Flask) with endpoints for user
registration and batch timestep sync — batched at session end, not streamed
live. — *Beyza*

> `backend/`: FastAPI. `POST /api/sessions` stores a session's summary,
> per-second events and device metrics; a retry of the same
> `(user_id, session_id)` answers ok without duplicating; clean and gap-only
> sessions are accepted, anything else gets `422`. 26 tests pass, run against
> payloads generated by the app's own code, and a live run over HTTP stored
> both kinds of session. Registration still goes through the Apps Script
> form; moving it here is not started.
>
> Registration can reuse the form's column list (minus the order columns
> removed by Decision 3). Swapping the form from Sheets to this API is a
> one-function change.

✅ **DONE** · Wire the API client in the app: HTTPS POST, retry logic, and a
device-identifier header on every request. — *Marthe*

> Built against `study/API_SCHEMA.md`: POST `/api/sessions`, `X-Device-Id`
> header (random per install), retry via the upload queue. Server address is
> set at build time: `--dart-define=API_BASE_URL=https://...`. Not yet tested
> against a real server.

> ✅ Participant ID entry is built: the home screen shows the ID (tap to
> edit, pre-filled with the saved one), Start Session asks for it if missing.
> Rule: at least 6 letters/numbers, stored exactly as typed. Every session stores
> `user_id`. The HTTPS client is built too (below).
>
> The onboarding form now asks the participant to choose their ID with the
> same rule, so the two always agree on format. What neither can catch is a
> typo or wrong capitalisation when the ID is typed into the app: those
> sessions silently match no consent record. Mitigations are in
> `study/README.md` — the strongest is for the server to refuse sessions
> whose `user_id` isn't registered.

🔶 **IN PROGRESS** · Set up the database (PostgreSQL/Supabase, or SQLite for an MVP)
storing user IDs, demographics, and time-series posture states. — *Beyza*

> Tables `sessions`, `posture_events`, `device_metrics` in
> `backend/app/models.py` (PostgreSQL in Docker, SQLite locally). Demographics
> stay in the onboarding Sheet for now and join on `user_id`.

> Keep names and emails in a separate restricted table from the research data.
> That separation is what makes the consent form's "pseudonymised" claim true
> in practice rather than only on paper.

🔶 **IN PROGRESS** · Containerize with Docker and configure deployment: reverse proxy
(Nginx) and SSL/HTTPS. — *Beyza*

> `backend/Dockerfile` and `docker-compose.yml` (API + PostgreSQL) run
> locally: both app-generated sessions were stored in PostgreSQL, the retry
> was not duplicated, and a bad `user_id` got `422`. Nginx and HTTPS, and a
> server to host them, are next.

✅ **DONE** · Provide mock testing payloads to verify the telemetry pipeline
behaves correctly before real data flows through it. — *Beyza*

> `backend/tests/fixtures/`: a clean and a gap-only session generated by the
> app's own `buildSessionPayload` and integrity check, plus malformed
> variants in `backend/tests/test_sessions.py`.

> Send them through the integrity checker first — its test suite already
> generates the interesting malformed cases.

---

## 4 — Study Design & User Testing

*Difficulty: Medium*

✅ **DONE** · Formulate the demographic survey: age, daily screen time,
baseline neck/back pain, desk setup. — *Beyza*

> All four are in the onboarding form, plus current pain on a 0–10 scale,
> treatment status, chair and screen height, how the phone is held, and phone
> model / Android version. Battery and temperature readings are not comparable
> across devices without those last two.

📌 **DECIDED** · Design the A/B study protocol — decide between-subject vs.
crossover design, session duration, and participant instructions. — *Beyza*

> **Between-subjects, chosen by the participant** (Decision 3, 15 October
> 2026). Replaces the counterbalanced crossover decided in September. Study
> length and session duration are still to be set.

### Design decision: one version per participant, self-selected

**What it means.** Each participant uses **one** feedback version for the
whole study: Version A (Dimming) or Version B (Baseline). They choose it
themselves with the buttons on the app's home screen. Nobody is assigned an
order, nobody switches versions, and there is no washout break.

**What it replaces.** The September plan was a counterbalanced crossover:
every participant used both versions, in an order (AB or BA) assigned by the
onboarding form, with a washout between phases.

**What this simplifies.**

- Participation is a single phase — shorter commitment, no reminder at a
  phase switch, no washout to explain.
- No learning effect from a first phase carrying into a second.
- The app needs no mode switching or enforcement; the participant's choice
  is the design.
- The onboarding form and Apps Script lose the order assignment.

**Limitations to report in the paper.**

- **Self-selection.** Participants choose their version, so the A and B groups
  may differ in ways that affect posture (for example, people who already
  care about posture may prefer one version). Compare the groups' baseline
  demographics — pain, screen time, previous posture aids — and report them.
- **Group size.** With under 30 participants split into two groups, differences
  between groups will be hard to show statistically. The September reasoning
  about between-person variance still applies; report effect sizes and
  confidence intervals rather than relying on significance alone.

**What this forces elsewhere.**

- Every session must carry `variant` — Section 3. *(Already sent by the
  app.)*
- Hide Version C — Section 2 (Decision 2).
- Remove the order assignment and phase/washout text from the form, the
  Apps Script and `study/README.md`, and rewrite the consent text for the
  one-version design (Decision 3). *(Done.)*
- Analysis compares the A group with the B group, using `variant` per
  participant.

---

⬜ **OPEN** · Distribute the APK / build variants to external Android
participants. — *Marthe*

> Participants also need their onboarding link, and the instruction to pick
> one version and keep it for the whole study.

⬜ **OPEN** · Be ready to provide in-person device troubleshooting if users
report crashes or the OS killing the background service. — *Marthe*

---

## 5 — Paper & Research Writing

*Difficulty: Easy–Medium*

⬜ **OPEN** · Select the target venue (CHI, MobileHCI, IMWUT/UbiComp, IEEE
Pervasive, etc.) early — this sets the page/word budget for everything else.
— *Beyza*

⬜ **OPEN** · Draft the System Architecture & Implementation section: pose
estimation pipeline, frame-throttling logic, feedback-trigger mechanism.
— *Together*

⬜ **OPEN** · Compile system benchmarks (FPS vs. battery life/temperature) from
the Section 1 stress tests, ready to drop into the paper. — *Beyza*

> Unblocked. Tables, limitations and a draft paragraph are in
> `study/results/SECTION1_RESULTS.md`.

⬜ **OPEN** · Draft Introduction, Related Work, and Methodology (User Study),
plus the data-analysis pipeline — these can start well before data collection
finishes. — *Beyza*

> The Methodology section can be written now: the design is settled and the
> consent and demographic instruments exist.

---

## 6 — Integration & Sign-off

*Difficulty: Easy*

⬜ **OPEN** · Run a full end-to-end test: Marthe connects the real device to
the deployed backend and verifies data lands correctly; Beyza checks the
database and API logs on the server side. — *Together*

> Add two checks (Decision 1): a session with a deliberate gap must arrive
> with `integrity.is_valid = false` and the right `gap_count`; a session with
> a deliberate backward timestamp must be refused by the integrity gate and
> never reach the server.

---

## How the study runs, end to end

### The participant's journey

1. **Onboarding.** Opens the consent form, reads what the study is and what
   the app records, ticks each consent statement individually, signs, and
   answers the demographic questions.
2. **Chooses an ID.** Picks their own participant ID (6+ letters/numbers, not
   their name). They copy it down or print the page, which doubles as their
   own copy of the signed consent.
3. **Setup.** Installs the app, types the ID in exactly as registered, and
   does the one-time 5-second calibration in a comfortable upright posture.
4. **Chooses a version.** Picks **A — Dimming** or **B — Baseline** on the
   app's home screen, and keeps it for the whole study.
5. **Uses the app** during normal phone use for the study length.
6. **Follow-up.** Optional short questionnaire, if they agreed to be contacted.

At any point they can email quoting their ID to withdraw, with no reason
required and no consequence.

### The researcher's workflow

| When | Who | What |
|---|---|---|
| Before recruiting | Beyza | Fill the form's placeholders; have the supervisor review the consent text; deploy the Apps Script backend; run the test submissions in `study/README.md`; delete the test rows |
| Per participant, at signup | Beyza | Send the form link; the backend checks the ID is free |
| Per participant, after signup | Marthe | Send the APK; remind them to pick one version and keep it |
| During the study | Both | Check each participant's uploaded `user_id` matches the Sheet, and that they use a single `variant`. Watch how many choose A vs. B — a very uneven split weakens the comparison |
| As sessions arrive | — | Each upload is validated by the integrity gate on the device before it is sent |
| At the end | Beyza | Export the Sheet to CSV, split identity columns from research columns, join sessions to demographics on `user_id` |

### How the two halves of the data meet

The onboarding form and the app never talk to each other. They produce two
separate datasets:

- **From the form** — consent record, demographics, device.
- **From the app** — per-second posture zones, session summaries, and device
  metrics every 15 s (battery, temperature, CPU, thermal status, app state);
  full list in `study/API_SCHEMA.md`.

`user_id` is the only thing joining them. The app checks its format but not
that it was registered, so a participant mistyping it into the app would
produce sessions that silently match no consent record — invisible during
collection and useless at analysis. Check the join during the study, not only
at the end.

---

## Immediate next actions

### Beyza

1. Decide study length and session duration — the form cannot be sent out
   until these are set.
2. Fill in the bracketed placeholders in the form — institution, contact
   email, retention period, study length (list in `study/README.md`). Nothing
   institutional was invented; every one is left blank on purpose.
3. Have the project supervisor review the consent text before recruiting
   anyone. It is a drafted text, not legal advice.
4. Deploy the Apps Script web app, paste its URL into the form, and run the
   test submissions in `study/README.md` (duplicate IDs). Delete the test rows
   afterwards.
5. Backend: choose a host and put Nginx + HTTPS in front of the Docker setup,
   so Marthe can point the app at it.

### Marthe

1. ~~Decision 1: upload gap-only sessions.~~ Done 20 Oct.
2. ~~Decision 2: hide the C button.~~ Done 20 Oct.
3. ~~Treat a `422` from the server as `blocked`.~~ Done 20 Oct.
4. ~~Test A and B on the phone.~~ Done 20 Oct.
5. Once Beyza's server is up: build with its address and run the Section 6
   end-to-end test, including a gap session.

Build note: the project path is too long for Windows' 260-character limit
and the build fails writing shader files. Build from a short drive
(`subst P: <project folder>`, then build in `P:\`) or enable Windows long
paths.

---

## Ordering note

Unchanged from the original plan: Sections 1–2 finish first; Section 3
(backend) and Section 5 (paper intro/related work) run in parallel with
Section 2 once the schema is defined; Section 4 (recruiting, distributing)
starts only once Sections 1–3 are validated end-to-end.

The task split remains by who can verify the work — device work to Marthe,
terminal-verifiable work to Beyza.

---

## Deliverables referenced above

| File | What it is |
|---|---|
| `lib/services/telemetry_integrity_service.dart` | Pure validator |
| `lib/services/telemetry_integrity_gate.dart` | Pre-upload gate, reads SQLite |
| `lib/models/integrity_report.dart` | Result types |
| `test/telemetry_integrity_service_test.dart` | 25 unit tests |
| `study/participant_onboarding.html` | Onboarding + consent form |
| `study/apps_script_backend.gs` | Google Sheets backend: ID check |
| `lib/services/participant_service.dart` | Participant ID rule and storage in the app |
| `lib/services/upload_service.dart` | Upload queue and HTTPS client |
| `study/README.md` | Setup guide for the form and backend |
| `study/API_SCHEMA.md` | Session upload payload (proposal, built in the app) |
| `study/results/SECTION1_RESULTS.md` | Device benchmarks, limitations, draft paper text |
| `study/results/session_metrics/` | Raw data for the five real-use runs |
