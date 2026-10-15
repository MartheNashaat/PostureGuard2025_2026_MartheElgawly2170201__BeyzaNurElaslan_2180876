# PostureGuard — Full Project Plan (annotated)

Priority ordering across pre-study validation, app engineering, backend, study
design, and the paper. Annotated 15 September 2026.

The original plan text is preserved; each task carries a status and a short
note on what was built or what changed.

## Where the project stands

- **Done** — Section 1 in full (device benchmarks, telemetry integrity checks,
  onboarding / consent form), frame-rate throttling, and the A/B feedback
  variants. Results in `study/results/SECTION1_RESULTS.md`.
- **Decided** — the A/B protocol is a **counterbalanced crossover**. See
  Section 4.
- **Proposed** — the session upload payload, in `study/API_SCHEMA.md`
  (includes `variant` and the device metrics). Needs Beyza's sign-off.

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

✅ **DONE** · Prepare user onboarding / consent forms (Google Form or a simple
web form) linked to each participant's unique user ID. — *Beyza*

> Self-contained HTML form — a Google Form cannot display a generated ID on
> its confirmation screen, which the requirement needs. Covers study
> description, granular informed consent, the Section 4 demographics, and
> issues a `PG-XXXX-XXXX` ID whose checksum catches 100% of single-character
> typos. Submissions go to Google Sheets via Apps Script until the real
> backend exists. Files in `study/`.

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
> ⚠️ The user now picks the mode, so the counterbalanced A/B order assigned by
> the onboarding form isn't enforced by the app. Decide how the study uses
> this (see Section 4).

> Crossover means each participant uses **both** versions, so the app must
> switch between them mid-study. One APK with a mode flag is preferred over
> two APKs, which would force an uninstall between phases and cost dropouts.
> Each uploaded session must carry which variant produced it.

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
> **Add `variant` (A or B) to every session.** Under crossover the same
> `user_id` produces sessions in both arms, so the participants table can no
> longer say which feedback produced a given reading — and that comparison is
> the whole study.

⬜ **OPEN** · Build the Web API (e.g. FastAPI or Flask) with endpoints for user
registration and batch timestep sync — batched at session end, not streamed
live. — *Beyza*

> Registration can reuse the form's column list. Swapping the form from Sheets
> to this API is a one-function change.

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
> ⚠️ This replaced the `PG-XXXX-XXXX` checksum IDs from the onboarding form,
> so the app no longer catches typos. Participants must type exactly the ID
> recorded against their consent form, or sessions won't join to it.

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

> **Counterbalanced crossover.** Rationale below. Session duration and phase
> lengths are still to be set; they are marked as placeholders in the form.

### Design decision: counterbalanced crossover

**What it means.** Every participant uses both feedback versions, one after
the other, with an app-free washout break in between. Half start with Version
A, half start with Version B.

**Why, in one line.** Recruitment is expected to be under 30 participants, and
between-subjects would be too underpowered to conclude anything at that size.

**The reasoning.** Baseline posture varies enormously between people — one
participant sits at 45, another at 85 — and that spread is wider than the
difference between the two feedback designs. Splitting 30 people into two
groups of 15 means any difference between group averages could just as easily
come from who landed in which group. In a crossover each participant is their
own control ("62 under A, 71 under B"), which removes between-person variance
and needs roughly 2–4× fewer participants for the same statistical power.

**The cost, and how it is handled.** Both versions teach posture awareness, so
participants are simply better at sitting by phase 2. Left alone this would
inflate whichever version came second. Two mitigations are already built into
the onboarding form:

1. **Counterbalancing** — the starting order is assigned server-side, giving
   whichever order currently has fewer participants, ties broken at random.
2. **A washout break** between the phases, with no app use at all.

At analysis time, include starting order as a factor and report whether it
interacts with the outcome. HCI reviewers expect that check.

**What this forces elsewhere.**

- The session payload needs a `variant` field — Section 3.
- The app must switch feedback modes between phases — Section 2.
- Participation is now two phases plus a break, so recruitment messaging must
  state the full time commitment.

**What would have changed this.** Recruiting 40+ participants. Between-subjects
is cleaner — no learning effect, simpler analysis, no mode switching, half the
commitment per person. If recruitment turns out much easier than expected,
revisit before phase 1 starts.

---

⬜ **OPEN** · Distribute the APK / build variants to external Android
participants. — *Marthe*

> Participants also need their onboarding link, and a reminder at the phase
> switch.

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

> Add one check: a session with a deliberate gap must be refused by the
> integrity gate before it reaches the server.

---

## How the study runs, end to end

### The participant's journey

1. **Onboarding.** Opens the consent form, reads what the study is and what
   the app records, ticks each consent statement individually, signs, and
   answers the demographic questions.
2. **Gets an ID.** The form issues a `PG-XXXX-XXXX` participant ID and tells
   them their phase order — for example *1st Version A (dimming), 2nd
   Version B (posture guide)*. They copy it down or print the page, which
   doubles as their own copy of the signed consent.
3. **Setup.** Installs the app, types the ID in, and does the one-time
   5-second calibration in a comfortable upright posture.
4. **Phase 1.** Uses the app during normal phone use, with their first
   feedback version, for the phase length.
5. **Washout.** Stops using the app entirely for the break period. This is not
   optional — it is what stops phase 1 from contaminating phase 2.
6. **Phase 2.** Switches to the second feedback version and carries on as
   before.
7. **Follow-up.** Optional short questionnaire, if they agreed to be contacted.

At any point they can email quoting their ID to withdraw, with no reason
required and no consequence.

### The researcher's workflow

| When | Who | What |
|---|---|---|
| Before recruiting | Beyza | Fill the form's 14 placeholders; get ethics approval; deploy the Apps Script backend; run three test submissions; delete the test rows |
| Per participant, at signup | Beyza | Send the form link; the backend assigns the counterbalanced order automatically |
| Per participant, after signup | Marthe | Send the APK or mode setting for their **phase 1** variant |
| At the phase boundary | Both | Remind the participant to pause for the washout, then switch them to the phase 2 variant — same participant ID throughout |
| During recruitment | Beyza | Run `groupCounts()` occasionally to confirm the `AB`/`BA` split stays even |
| As sessions arrive | — | Each upload is validated by the integrity gate on the device before it is sent |
| At the end | Beyza | Export the Sheet to CSV, split identity columns from research columns, join sessions to demographics on `user_id` |

### How the two halves of the data meet

The onboarding form and the app never talk to each other. They produce two
separate datasets:

- **From the form** — consent record, demographics, device, assigned sequence.
- **From the app** — per-second posture readings, scores, zones, streaks,
  battery, temperature.

`user_id` is the only thing joining them, which is why the ID carries a
checksum: a participant mistyping it into the app would produce sessions that
silently match no consent record, invisible during collection and useless at
analysis.

---

## Immediate next actions

### Beyza

1. Fill in the 14 bracketed placeholders in the onboarding form — institution,
   ethics approval, contact email, retention period, phase lengths. Nothing
   institutional was invented; every one is left blank on purpose.
2. Send the consent text to the ethics committee for approval before
   recruiting anyone. It is a drafted text, not legal advice.
3. Deploy the Apps Script web app, paste its URL into the form, and submit
   three test entries to confirm the order assignment balances. Delete the
   test rows afterwards.
4. Add `variant` to the session schema before writing any endpoint.
5. Decide phase length, washout length, and session duration — the form cannot
   be sent out until these are set.

### Marthe

1. Test both variants on the phone (long-press the logo to switch).
2. Once Beyza's server is up: build with its address and run the Section 6
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
| `study/apps_script_backend.gs` | Google Sheets backend, order assignment |
| `study/participant_id_validator.dart` | ID validator for the app |
| `study/README.md` | Setup guide for the form and backend |
| `study/API_SCHEMA.md` | Proposed session upload payload |
| `study/results/SECTION1_RESULTS.md` | Device benchmarks, limitations, draft paper text |
| `study/results/session_metrics/` | Raw data for the five real-use runs |
