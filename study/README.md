# Participant Onboarding — Setup Guide

Covers the Section 4 plan item *"Prepare user onboarding / consent forms
linked to each participant's unique user ID."*

| File | What it is |
|---|---|
| `participant_onboarding.html` | The form. Self-contained — no framework, no CDN, no build step. Open it in any browser. |
| `apps_script_backend.gs` | Google Apps Script that receives submissions, checks the participant ID is free, assigns the A/B order, and writes to a Sheet. |
| `API_SCHEMA.md` | What the app uploads per session. Section 2 of the form describes the same fields to participants. |

---

## Why a web form and not a Google Form

Google Forms cannot show a computed value on its confirmation screen — only
static text. Even with Apps Script, the `onFormSubmit` trigger fires *after*
submission and cannot alter the confirmation page. The participant needs to
see their **assigned phase order** (A then B, or B then A) at the end, which
is computed by the backend at submission time, so a Google Form can't do it.

The HTML form also:

- checks the participant ID against the app's rule *before* submitting, and
  tells the participant immediately if the ID is already taken;
- lets participants print or save their own copy of the signed consent, which
  ethics committees generally expect;
- lays out the consent items as separately tickable statements rather than
  one blanket agreement.

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

Left empty, the form still works: it shows the participant's ID, a locally
alternated phase order, and their answers as JSON for manual copying. It
cannot check whether the ID is already taken in this mode. Useful for
testing, and as a safety net — a network failure never costs a participant
their responses.

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
5. Try to reuse an ID from step 1, also with different upper/lower case — it
   must be refused as "already taken". Try an ID containing the test name —
   also refused.
6. Print the confirmation screen to PDF and check the participant ID is legible.
7. **Delete the test rows before recruiting**, or they will skew the A/B
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

**Chosen by the participant**, at the end of the form. The rule is the app's
(`lib/services/participant_service.dart`), so an ID the form accepts is always
one the app accepts:

- **At least 6 characters, letters and numbers only** — no spaces, dashes or
  symbols. The form caps it at 20, the app's input limit.
- **Case-sensitive, stored exactly as typed.** `Tiger42x` and `tiger42x` are
  different IDs in the app. Only spaces at the ends are removed.
- **Unique, ignoring case.** The backend refuses an ID that is already in the
  Sheet in any capitalisation, so two participants can't end up with
  look-alike IDs. The form then asks the participant to pick another one.
- **Must not contain the participant's name or email.** The form refuses an ID
  that contains any 3+ letter part of the typed name or email address. This
  matters: the ID is the only thing on the research data that points back to
  a person, and "pseudonymised" stops being true if the ID is `Ayse1995`.
- Stored as plain text in the Sheet, so an all-digit ID like `001234` keeps
  its leading zeros.

### Typos are not caught

The app checks the *format* of the ID, not that it matches a registration. A
participant who registered `Tiger42x` and types `Tiger42X` into the app gets
sessions that silently match no consent record — invisible during collection
and useless at analysis.

Mitigations, in order of effort:

1. The confirmation screen tells participants case matters and offers copy
   and print.
2. At the phase boundary, compare the `user_id`s arriving from the app against
   the Sheet and contact anyone whose sessions don't match.
3. Once the Section 3 server exists, it can refuse sessions whose `user_id` is
   not registered, and the app can show that error.

---

## Study design: counterbalanced crossover

**Decided.** Expected recruitment is under 30 participants, which is what
settles it.

Section 2 of the plan defines two arms — Version A (dimming only) and Version B
(baseline overlay) — with identical detection and logging. Every participant
uses **both**, one after the other.

The app also has a **Version C (both at once)**. It is not one of the study's
two arms and the form never assigns it; see the open question under *What the
app does* below.

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

### The `variant` field

The same `user_id` produces sessions under both arms, so every uploaded
session carries `variant` (`A`, `B` or `C`) — see `API_SCHEMA.md`. Without it
the participants table could not tell you which feedback produced a given
reading, and that comparison is the entire study.

The participants sheet separately records `sequence` (`AB` or `BA`),
`phase1_variant` and `phase2_variant`. Comparing those with the `variant` on
each uploaded session is how you check a participant actually used the
version they were assigned in each phase.

### What the app does

One APK. Three buttons on the home screen choose the feedback — **A —
Dimming**, **B — Baseline**, **C — Both** — and the choice is remembered
between sessions. No session can start until one is chosen.

**Open question:** the participant picks the button, so the app does not
enforce the order the form assigned. As things stand, the form tells them
which version to select for phase 1, and the researcher reminds them to switch
at the phase boundary. Decide before recruiting whether that is enough, or
whether the app should hide C and/or lock the variant for study participants.

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
{ "ok": true, "sequence": "AB" }
{ "ok": false, "error": "duplicate user_id" }
```

Everything else — validation, the confirmation screen, the offline
fallback — is independent of where the data goes. Keep the server-side checks
the Apps Script does: the ID rule, and uniqueness ignoring case.

The `COLUMNS` array in `apps_script_backend.gs` doubles as the column list for
the `participants` table when you write the schema.
