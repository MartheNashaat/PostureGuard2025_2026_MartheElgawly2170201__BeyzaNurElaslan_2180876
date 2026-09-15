# Participant Onboarding — Setup Guide

Covers the Section 4 plan item *"Prepare user onboarding / consent forms
linked to each participant's unique user ID."*

| File | What it is |
|---|---|
| `participant_onboarding.html` | The form. Self-contained — no framework, no CDN, no build step. Open it in any browser. |
| `apps_script_backend.gs` | Google Apps Script that receives submissions, assigns the A/B variant, and writes to a Sheet. |
| `participant_id_validator.dart` | Paste-ready ID validator for the app, so a mistyped ID is rejected at entry. Runs its own self-test. |

---

## Why a web form and not a Google Form

Google Forms cannot show a generated value on its confirmation screen — only
static text. Even with Apps Script, the `onFormSubmit` trigger fires *after*
submission and cannot alter the confirmation page. That makes the requirement
"generate a unique `user_id` and show it to the participant at the end"
structurally impossible there. The remaining workarounds either collect an
email address to send the ID (which weakens anonymity) or pre-generate a list
of IDs to hand out by hand.

The HTML form also lets participants print or save their own copy of the
signed consent, which ethics committees generally expect, and lays out the
consent items as separately tickable statements rather than one blanket
agreement.

---

## Step 1 — Fill in the placeholders (required before real use)

The form ships with every institution-specific detail left blank on purpose.
Nothing about your university, ethics approval, or contacts was invented.
Each appears as a yellow dashed box in the browser. Search the HTML for `[`
and replace all of these:

| Placeholder | What goes there |
|---|---|
| `[INSTITUTION / DEPARTMENT]` | University and department running the study |
| `[RESEARCHER NAMES]` | Both researchers |
| `[CONTACT EMAIL]` | Study contact address — appears in three places |
| `[ETHICS COMMITTEE]` | Committee that reviewed the study |
| `[APPROVAL NUMBER]` | Their approval reference |
| `[INDEPENDENT CONTACT / DATA PROTECTION OFFICER]` | Independent complaints contact |
| `[PHASE LENGTH]` | How long each of the two phases lasts, e.g. 5 days — appears twice |
| `[WASHOUT PERIOD]` | The app-free break between phases, e.g. 2 days — appears twice |
| `[TOTAL DURATION]` | Phase 1 + washout + phase 2, so participants see the full commitment |
| `[SESSION DURATION]` | Length of one monitoring session |
| `[COMPENSATION, or: …]` | Payment, credit, or none |
| `[STORAGE LOCATION / PROVIDER / COUNTRY]` | Where the data physically lives |
| `[RETENTION PERIOD]` | How long you keep it before deletion |
| `[GDPR Art. 6(1)(a) or applicable basis]` | Legal basis for processing |

> **This is a draft, not legal advice.** The consent wording is modelled on
> standard practice, but your ethics committee must review and approve the
> final text before you recruit anyone.

Two decisions are already baked into the wording and should stay consistent
with what you actually do:

- **Pseudonymous, not anonymous.** The form collects a name and email and
  states plainly that a restricted list links them to the `user_id`. That link
  is what makes a withdrawal request possible. If you later decide to keep no
  such list, the text in section 2 must change too — claiming anonymity while
  holding a mapping would be a misstatement.
- **18+ only.** Under-18s need parental consent, which this form does not
  handle. Eligibility is checked twice: a consent checkbox and a validated age
  field.

---

## Step 2 — Create the Sheet and deploy the backend

1. Create a new Google Sheet, named e.g. `PostureGuard Participants`.
2. **Extensions → Apps Script**. Delete the placeholder `myFunction`.
3. Paste the whole of `apps_script_backend.gs`. Save.
4. Run `selfTest` once from the editor. Google will ask you to authorise the
   script — accept. Check the execution log: it should report the sheet is
   ready. This also creates the `participants` tab with its header row.
5. **Deploy → New deployment → Web app**:
   - Description: `PostureGuard onboarding`
   - **Execute as:** Me
   - **Who has access:** Anyone
6. Copy the deployment URL. It ends in `/exec`.

> "Anyone" means anyone who has the URL can POST to it. It does not make your
> Sheet public — only this script can write, and only in the shape it defines.
> Treat the URL as a secret: do not commit it to a public repository.

**Every time you edit the script**, you must deploy again
(**Deploy → Manage deployments → edit → New version**), or the live endpoint
keeps running the old code. This trips people up constantly.

---

## Step 3 — Connect the form

Open `participant_onboarding.html` and set the URL near the top of the
`<script>` block:

```js
var ENDPOINT = "https://script.google.com/macros/s/AKfycb.../exec";
```

Left empty, the form still works: it generates the ID and shows the
participant's answers as JSON for manual copying. Useful for testing, and as a
safety net — a network failure never costs a participant their responses.

The request is sent as `Content-Type: text/plain` on purpose. Apps Script web
apps do not answer CORS preflight requests, so `application/json` would fail in
the browser. Apps Script reads the body from `e.postData.contents` either way.

---

## Step 4 — Test before recruiting

1. Open the file in a browser and submit once with made-up answers.
2. Check the Sheet: one row, with a `user_id`, a `variant`, and a
   `received_at` timestamp.
3. Submit twice more and confirm the variants balance (A, B, A, B…).
4. Try to submit with a consent box unticked, and with age 17 — both must be
   refused with a message.
5. Print the confirmation screen to PDF and check the participant ID is legible.
6. **Delete the test rows before recruiting**, or they will skew the A/B
   allocation counts.

---

## Step 5 — Hosting

| How | When it fits |
|---|---|
| Open the local file | In-person onboarding on your own laptop. Simplest, nothing to host. |
| Email the `.html` file | Participants open it locally. Works, but some mail clients strip attachments. |
| GitHub Pages | Remote participants, shareable link. Free. Put the file in a **private-repo-backed** Pages site or accept that the form markup is public — the `ENDPOINT` URL would be visible in source. |
| Your own server | Best once the Section 3 backend exists. |

Because the endpoint URL is visible in page source when hosted, prefer
in-person or emailed use while recruitment is small.

---

## The participant ID

Format: `PG-XXXX-XXXX` — a `PG-` prefix plus 8 characters.

- **Alphabet:** Crockford Base32 — the digits and letters minus `I`, `L`, `O`
  and `U`, so `1`/`I` and `0`/`O` cannot be confused when read off paper.
- **7 random characters** from `crypto.getRandomValues`, with rejection
  sampling so every symbol is equally likely. That is 32⁷ ≈ 3.4 × 10¹⁰
  possible IDs; at 100 participants the chance of *any* collision is about
  1.5 × 10⁻⁷.
- **The 8th character is a Luhn mod-32 checksum.** Verified empirically:
  **100% of single-character typos** and **99.8% of adjacent transpositions**
  are detected.

The checksum is the point. Participants type this ID into the app by hand. A
mistyped ID does not fail loudly — it produces sessions tagged with an ID that
matches no consent record, which is invisible during collection and useless at
analysis. Validating at entry turns that silent data loss into an immediate
"check your ID" message.

### Wiring the check into the app

Copy `ParticipantId` from `participant_id_validator.dart` into
`lib/services/participant_id.dart` and call it on the ID entry screen:

```dart
final id = ParticipantId.normalize(controller.text);
if (id == null) {
  setState(() => _error = 'That ID does not look right — please check it.');
  return;
}
// `id` is now canonical: PG-XXXX-XXXX, ready to send as user_id.
```

`normalize` accepts what people actually type: any case, with or without the
dashes and the `PG-` prefix, and it folds `I`/`L` to `1` and `O` to `0` per
the Crockford convention.

Self-test (24 assertions, including every possible single-character typo on
five real IDs generated by the HTML form):

```bash
dart run study/participant_id_validator.dart
```

---

## Study design: counterbalanced crossover

**Decided.** Expected recruitment is under 30 participants, which is what
settles it.

Section 2 of the plan defines two arms — Version A (dimming only) and Version B
(baseline overlay) — with identical detection and logging. Every participant
uses **both**, one after the other.

### Why crossover and not between-subjects

Posture varies enormously between people: one participant's baseline score is
45, another's is 85, and that spread is larger than the difference the study is
trying to measure. Split 30 participants into two groups of 15 and any
difference between the group averages could just as easily come from which
people landed in which group.

In a crossover design each participant is their own control — "this person
scored 62 under A and 71 under B" — which removes between-person variance
entirely and needs roughly 2–4× fewer participants for the same statistical
power. Below 30 participants, between-subjects would most likely produce a
result too noisy to claim anything from.

### The cost, and how it is handled

Both versions teach posture awareness, so a participant is genuinely better at
sitting by the time phase 2 begins. Left alone, that improvement would inflate
whichever version came second.

Two mitigations, both built in:

1. **Counterbalancing.** Half the participants start with A, half with B, so
   the learning effect lands on both versions equally. `assignSequence()` does
   this server-side, giving whichever starting order currently has fewer
   participants and breaking ties at random. Counting live rows rather than
   keeping a counter keeps the split even when someone abandons the form
   halfway, and correct if you delete a test row.
2. **A washout break** between phases, with no app use at all. Set its length
   in the form's `[WASHOUT PERIOD]` placeholder.

At analysis time, include the starting order as a factor and check whether it
interacts with the outcome. If it does, that is an order effect and must be
reported — reviewers at HCI venues expect to see this check.

`LockService` serialises submissions. Without it, two people finishing the form
in the same second would both read the same counts and both get the same
starting order.

Run `groupCounts()` from the Apps Script editor during recruitment to see the
current split.

### Required change to the backend schema

The payload schema in the plan's Section 3 is:

```
user_id, session_id, timestamp, score, zone, streak, battery, temperature, app_version
```

Crossover makes a **`variant` field on every session mandatory**. The same
`user_id` now produces sessions under both arms, so the participants table can
no longer tell you which feedback mechanism produced a given reading — and that
comparison is the entire study.

```
user_id, session_id, timestamp, score, zone, streak, battery, temperature, app_version, variant
```

`variant` holds `A` or `B` per session. The participants sheet separately
records `sequence` (`AB` or `BA`), `phase1_variant` and `phase2_variant`, which
is what lets you verify that a participant's uploaded sessions actually match
the order they were assigned.

### What the app needs

The app must be able to run either feedback mode, and switch between them
between phases. Two options:

- **One APK, a mode flag.** The app asks the server which variant applies, or
  reads a setting the researcher flips. Preferred: no reinstall, no risk of a
  participant running the wrong build.
- **Two APKs.** Simpler to build, but participants must uninstall and reinstall
  between phases, which costs dropouts.

Detection and logging are already identical across both variants, so this is a
feedback-layer switch rather than a second implementation.

---

## Where the data lands

The `participants` sheet holds everything in one table for convenience. For the
real study, split it:

- **Linking list** — `user_id`, `full_name`, `email`, `signature`,
  `signed_date`. Restricted access, separate file, not shared with anyone
  outside the research team.
- **Research data** — `user_id`, `variant`, and the demographic and device
  answers. This is what you analyse and what can be shared or published
  alongside the session telemetry.

Keeping them apart is what makes "pseudonymised" true in practice rather than
just in the consent text. `apps_script_backend.gs` writes the identity columns
in one contiguous block, so splitting is a column-range copy.

**CSV export:** File → Download → Comma-separated values, on the
`participants` tab.

---

## Moving to the real backend later

Section 3 replaces the Sheet with FastAPI/Flask plus Postgres. Only one
function in the HTML needs to change — `send()`. Point `ENDPOINT` at your own
route and keep the response contract:

```json
{ "ok": true, "variant": "A" }
```

Everything else — ID generation, validation, the confirmation screen, the
offline fallback — is independent of where the data goes.

The `COLUMNS` array in `apps_script_backend.gs` doubles as the column list for
the `participants` table when you write the schema.
