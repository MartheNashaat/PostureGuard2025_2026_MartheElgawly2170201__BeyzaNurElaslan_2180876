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
- **Proposed** — the session upload payload, in `study/API_SCHEMA.md`
  (includes `variant` and the device metrics). Needs Beyza's sign-off.
- **Participant IDs** — chosen by the participant (6+ letters/numbers,
  case-sensitive), in both the app and the onboarding form. The earlier
  `PG-XXXX-XXXX` generated IDs are gone.
- **Decided** — Version C (both) is hidden from participants for now.
- **Decided** — sessions whose only defect is gaps are uploaded with the gap
  count; only seriously broken sessions are blocked. See Section 1.

### Decisions of 15 October 2026

| # | Decision | What changes | Who |
|---|---|---|---|
| 1 | **Gap-only sessions are uploaded.** Clean sessions are uploaded as before (`is_valid = true`). A session whose only problem is gaps (a few seconds missing because Android throttled the app) is sent with `integrity.is_valid = false` and its `gap_count`. Sessions with out-of-order or duplicate timestamps, missing timestamps, a summary that disagrees with its events, or no events at all stay blocked. | App: the gate/upload rule changes from "block on any issue" to "block unless `hasOnlyGaps`". Server: must accept `is_valid = false`. `study/API_SCHEMA.md` updated. | Marthe (app), Beyza (server) |
| 2 | **Version C (both) is hidden** from participants for now. Only A and B can be selected. | App: hide the C button. | Marthe |
| 3 | **Each participant chooses one version and uses only that one.** No assigned order, no second phase, no washout. The participant picks A (Dimming) or B (Baseline) with the buttons on the app's home screen. | Form, Apps Script and `study/README.md`: remove the AB/BA order assignment, the phase and washout text, and the order shown on the confirmation screen. Consent text must describe the new design. | Beyza |

Nothing is implemented yet — these are recorded here so the code and form can
be changed later. Each affected task below carries a ⚠️.

| Status | Meaning |
|---|---|
| ✅ **DONE** | Built and tested |
| 📌 **DECIDED** | Settled, nothing to build |
| ⚠️ **UPDATE** | Written, but now needs revising |
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
> ⚠️ **Decision 1 (15 Oct):** the gate currently blocks every session with
> any issue, gaps included. Gap-only sessions (`report.hasOnlyGaps`) must be
> uploaded with their gap count instead; everything else stays blocked. Not
> yet changed in code.

✅ **DONE** · Prepare user onboarding / consent forms (Google Form or a simple
web form) linked to each participant's unique user ID. — *Beyza*

> ⚠️ **Decision 3 (15 Oct):** remove the AB/BA order, the phase and washout
> text, and the order on the confirmation screen from the form, the Apps
> Script and `study/README.md`; rewrite the study description for the
> one-version design. Not yet changed.
>
> Self-contained HTML form — a Google Form cannot display the assigned phase
> order on its confirmation screen, which the crossover needed. Covers study
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
> stay in all three. Each session stores its variant. Still to check on the
> phone.
>
> ⚠️ **Decision 2 (15 Oct):** hide the C button from participants for now;
> participants choose between A and B only. Not yet changed in code.
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
> home screen opens. The integrity check runs before sending, as below;
> failing sessions are marked `blocked` and kept on the phone.

> Run the integrity check before the queue flushes, not after, so a corrupted
> session is caught on the device.

---

## 3 — Backend & Cloud Deployment

*Difficulty: Medium–Hard*

⚠️ **UPDATE** · Define the exact JSON schema / API payload before writing
endpoints (fields: `user_id`, `session_id`, `timestamp`, `score`, `zone`,
`streak`, `battery`, `temperature`, `app_version`). — *Beyza*

> Proposal written: `study/API_SCHEMA.md`. Open question for Beyza: the app
> logs the zone every second but not the 0–100 score — is the score needed?
>
> `variant` is in the proposal and the app already sends it. Participants
> can only select `A` or `B` (C hidden, Decision 2). Each participant chooses
> one version (Decision 3), so `variant` is what puts a participant's
> sessions in the A or B group — the comparison the study is about.
>
> Decision 1 is reflected in the schema: `integrity.is_valid` can be `false`
> for gap-only sessions, and the server must accept them.

⬜ **OPEN** · Build the Web API (e.g. FastAPI or Flask) with endpoints for user
registration and batch timestep sync — batched at session end, not streamed
live. — *Beyza*

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

⬜ **OPEN** · Set up the database (PostgreSQL/Supabase, or SQLite for an MVP)
storing user IDs, demographics, and time-series posture states. — *Beyza*

> Keep names and emails in a separate restricted table from the research data.
> That separation is what makes the consent form's "pseudonymised" claim true
> in practice rather than only on paper.

⬜ **OPEN** · Containerize with Docker and configure deployment: reverse proxy
(Nginx) and SSL/HTTPS. — *Beyza*

⬜ **OPEN** · Provide mock testing payloads to verify the telemetry pipeline
behaves correctly before real data flows through it. — *Beyza*

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
  one-version design (Decision 3).
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
| Before recruiting | Beyza | Update the form for Decision 3; fill its placeholders; get ethics approval; deploy the Apps Script backend; run the test submissions in `study/README.md`; delete the test rows |
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

1. Update the onboarding form, Apps Script and `study/README.md` for
   Decision 3: remove the order assignment and phase/washout text, and
   rewrite the study description and consent text for the one-version design.
2. Fill in the bracketed placeholders in the form — institution, ethics
   approval, contact email, retention period, study length. Nothing
   institutional was invented; every one is left blank on purpose.
3. Send the consent text to the ethics committee for approval before
   recruiting anyone. It is a drafted text, not legal advice.
4. Deploy the Apps Script web app, paste its URL into the form, and run the
   test submissions in `study/README.md` (duplicate IDs). Delete the test rows
   afterwards.
5. Sign off `study/API_SCHEMA.md` before writing any endpoint — still open:
   whether the per-second 0–100 score is needed. The server must accept
   gap-only sessions (`is_valid = false`).
6. Decide study length and session duration — the form cannot be sent out
   until these are set.

### Marthe

1. Decision 1: upload gap-only sessions (`report.hasOnlyGaps`) with their gap
   count; keep blocking every other integrity failure.
2. Decision 2: hide the C button from participants.
3. Test A and B on the phone.
4. Once Beyza's server is up: build with its address and run the Section 6
   end-to-end test.

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
| `study/apps_script_backend.gs` | Google Sheets backend: ID check (order assignment to be removed, Decision 3) |
| `lib/services/participant_service.dart` | Participant ID rule and storage in the app |
| `lib/services/upload_service.dart` | Upload queue and HTTPS client |
| `study/README.md` | Setup guide for the form and backend |
| `study/API_SCHEMA.md` | Session upload payload (proposal, built in the app) |
| `study/results/SECTION1_RESULTS.md` | Device benchmarks, limitations, draft paper text |
| `study/results/session_metrics/` | Raw data for the five real-use runs |
