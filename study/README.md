# Participant Onboarding — Setup Guide

Covers the Section 4 plan item *"Prepare user onboarding / consent forms
linked to each participant's unique user ID."*

| File | What it is |
|---|---|
| `participant_onboarding.html` | The form. Self-contained — no framework, no CDN, no build step. Open it in any browser. |
| `../backend/` | The study server. Serves the form at `/onboarding`, receives submissions at `POST /api/participants`, checks the participant ID is free. |
| `apps_script_backend.gs` | **No longer used** (18 November 2026). The earlier Google Sheets backend, kept for reference. |
| `API_SCHEMA.md` | What the app uploads per session. Section 2 of the form describes the same fields to participants. |

---

## Why a web form and not a Google Form

The participant chooses their own ID, and it must follow the app's rule and
not already be taken. A Google Form can check a pattern, but it cannot check
the ID against earlier submissions and ask for another one. The HTML form
also:

- refuses an ID that contains the participant's name or email;
- shows the ID on the confirmation screen and lets participants print or save
  their own copy of the signed consent;
- lays out the consent items as separately tickable statements rather than
  one blanket agreement.

---

## Step 1 — Fill in the placeholders (required before real use)

The form ships with every institution-specific detail left blank on purpose.
Nothing about your university or contacts was invented.
Each appears as a yellow dashed box in the browser. Search the HTML for `[`
and replace all of these:

| Placeholder | What goes there |
|---|---|
| `[INSTITUTION / DEPARTMENT]` | University and department running the study |
| `[RESEARCHER NAMES]` | Both researchers |
| `[CONTACT EMAIL]` | Study contact address — appears in four places |
| `[INDEPENDENT CONTACT / DATA PROTECTION OFFICER]` | Independent complaints contact |
| `[STUDY LENGTH]` | How long participants use the app, e.g. 7 days — appears twice |
| `[SESSION DURATION]` | Length of one monitoring session |
| `[COMPENSATION, or: …]` | Payment, credit, or none |
| `[STORAGE LOCATION / PROVIDER / COUNTRY]` | Where the data physically lives |
| `[RETENTION PERIOD]` | How long you keep it before deletion |
| `[GDPR Art. 6(1)(a) or applicable basis]` | Legal basis for processing |

> **This is a draft, not legal advice.** The consent wording is modelled on
> standard practice. No ethics committee approval is required for this study;
> the form states that it is carried out with the approval of the project
> supervisor, so have the supervisor review the final text before you recruit
> anyone.

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

## Step 2 — Where the form runs

**Decided 18 November 2026:** registrations go to the study server, not to a
Google Sheet. The server is hosted by Sapienza and serves the form itself:

```
https://postureguard.test.sapienzaapps.it/onboarding
```

That is the link participants get. Served from there, the form posts to
`/api/participants` on the same server, so there is no endpoint URL to set
and no cross-site request. Setup of the server: `backend/README.md`.

Opened as a local file (double-clicked), the form runs in **offline mode**:
it shows the participant's ID and their answers as JSON for manual copying,
and cannot check whether the ID is taken. Useful for testing the layout, and
as a safety net — a network failure never costs a participant their
responses.

---

## Step 3 — Test before recruiting

1. Open the `/onboarding` link and submit once with made-up answers.
2. On the server, `docker compose exec api python -m scripts.status` should
   show one registered participant.
3. Try to submit with a consent box unticked, and with age 17 — both must be
   refused with a message.
4. Try to reuse an ID from step 1, also with different upper/lower case — it
   must be refused as "already taken". Try an ID containing the test name —
   also refused.
5. Print the confirmation screen to PDF and check the participant ID is legible.
6. **Delete the test registrations before recruiting**, or their IDs stay
   taken:
   ```bash
   docker compose exec db psql -U postureguard -c \
     "DELETE FROM participants WHERE user_id = '<test id>';"
   ```
   The matching `participant_identities` row goes with it.
7. Set `REQUIRE_REGISTERED_USER=true` in `backend/.env` and run
   `docker compose up -d`, so sessions from unregistered IDs are refused.

---

## The participant ID

**Chosen by the participant**, at the end of the form. The rule is the app's
(`lib/services/participant_service.dart`), so an ID the form accepts is always
one the app accepts:

- **At least 6 characters, letters and numbers only** — no spaces, dashes or
  symbols. The form caps it at 20, the app's input limit.
- **Case-sensitive, stored exactly as typed.** `Tiger42x` and `tiger42x` are
  different IDs in the app. Only spaces at the ends are removed.
- **Unique, ignoring case.** The server refuses an ID that is already
  registered in any capitalisation, so two participants can't end up with
  look-alike IDs. The form then asks the participant to pick another one.
- **Must not contain the participant's name or email.** The form refuses an ID
  that contains any 3+ letter part of the typed name or email address. This
  matters: the ID is the only thing on the research data that points back to
  a person, and "pseudonymised" stops being true if the ID is `Ayse1995`.
- Stored as text, so an all-digit ID like `001234` keeps its leading zeros.

### Typos are not caught

The app checks the *format* of the ID, not that it matches a registration. A
participant who registered `Tiger42x` and types `Tiger42X` into the app gets
sessions that silently match no consent record — invisible during collection
and useless at analysis.

Mitigations, in order of effort:

1. The confirmation screen tells participants case matters and offers copy
   and print.
2. During the study, `scripts.status` on the server lists every uploaded
   `user_id` with no registration, and says when only the capitalisation
   differs. Contact those participants.
3. With `REQUIRE_REGISTERED_USER=true` the server refuses those sessions
   (`422`), so they never mix into the data. The app should then tell the
   participant to check their ID — to be added in the app (Marthe).

---

## Study design: one version per participant

**Decided 15 October 2026** (see `PROJECT_PLAN.md`, Section 4). Each
participant chooses **one** feedback version on the app's home screen —
**A — Dimming** or **B — Baseline** — and uses only that one for the whole
study. Nothing is assigned by the form or the backend, and there are no
phases or washout break.

This replaces the counterbalanced crossover planned in September, where every
participant used both versions in an order (AB or BA) assigned by this
backend.

### The `variant` field

The version is not recorded on the form. It arrives with every uploaded
session as `variant` (`A` or `B`) — see `API_SCHEMA.md` — and that is what
puts a participant in the A or B group at analysis time.

The app still lets participants change their choice at any time, so tell them
to keep the version they picked, and check at analysis that each `user_id`
has a single `variant`. Version C (both) is hidden from participants
(since 20 October 2026); it remains for internal testing only.

---

## Where the data lands

On the study server, in two kinds of table:

- **Linking list** — `participant_identities`: `user_id`, `full_name`,
  `email`, `signature`, `signed_date`. Needed to act on a withdrawal
  request. Not shared with anyone outside the research team.
- **Research data** — `participants` (consent answers, demographics,
  device) and the session tables, all joined on `user_id`. This is what you
  analyse and what can be shared or published.

Keeping them apart is what makes "pseudonymised" true in practice rather than
just in the consent text.

**CSV export:** `docker compose exec api python -m scripts.export /srv/export`
writes the research tables only; `--with-identities` adds `identities.csv`,
to be stored separately. See `backend/README.md`.
