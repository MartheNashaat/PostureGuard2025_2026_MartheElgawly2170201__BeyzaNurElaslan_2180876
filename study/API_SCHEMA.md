# Session upload — API payload schema

What the app sends to the server at the end of each session. The endpoints
and database tables should be built against it.

**Status:** agreed (16 October 2026). Implemented in the app
(`lib/services/upload_payload.dart`) and in the server (`backend/`).

---

## How uploads work

- **One request per session, sent when the session ends.** Nothing is streamed
  live. The app stores everything in SQLite during the session, runs the
  telemetry integrity check, and only then uploads.
- **Retries will happen.** If the network drops, the app re-sends the same
  session later. The server must treat `(user_id, session_id)` as unique and
  ignore or overwrite a duplicate — not insert it twice.
- **All timestamps are Unix epoch milliseconds (UTC)**, as integers.

```
POST /api/sessions
Content-Type: application/json
X-Device-Id: <stable per-install id>
```

Response: `{ "ok": true }` on success (including a duplicate that was
ignored). Any non-2xx response makes the app retry later.

---

## Payload

```json
{
  "user_id": "AB12CD",
  "session_id": "1790599044037",
  "variant": "A",
  "app_version": "1.0.0+1",

  "session": {
    "started_at": 1790599044183,
    "ended_at": 1790602646922,
    "duration_seconds": 3602,
    "good_posture_percent": 41.7,
    "longest_streak_seconds": 212,
    "worst_moment_timestamp": 1790600821000
  },

  "device": {
    "manufacturer": "samsung",
    "model": "SM-A546B",
    "android_version": "14",
    "cpu_cores": 10
  },

  "detection": {
    "foreground_fps": 15,
    "pip_fps": 3
  },

  "integrity": {
    "is_valid": true,
    "gap_count": 0,
    "missing_count": 0
  },

  "events": [
    { "t": 1790599045000, "status": 0 },
    { "t": 1790599046000, "status": 1 }
  ],

  "device_metrics": [
    {
      "t": 1790599044183,
      "battery_percent": 80.0,
      "battery_temperature_c": 30.6,
      "is_charging": false,
      "thermal_status": "none",
      "cpu_percent": null,
      "is_screen_on": true,
      "is_power_save": false,
      "app_state": "foreground"
    }
  ],

  "device_metrics_summary": {
    "sample_count": 242,
    "duration_seconds": 3603,
    "start_battery_percent": 80.0,
    "end_battery_percent": 59.0,
    "battery_drop_percent": 21.0,
    "discharge_seconds": 3603,
    "battery_percent_per_hour": 20.98,
    "charged_during_session": false,
    "avg_cpu_percent": 11.1,
    "max_cpu_percent": 24.3,
    "avg_battery_temp_c": 41.5,
    "max_battery_temp_c": 43.6,
    "worst_thermal_status": "moderate",
    "pip_percent": 96.0,
    "background_percent": 0.0,
    "power_save_percent": 0.0
  }
}
```

### Field reference

| Field | Type | Notes |
|---|---|---|
| `user_id` | string | Participant ID entered on the phone: 6+ letters/numbers, stored exactly as typed (case-sensitive). Set once per phone and kept until the user edits it. Groups sessions per participant. The participant chooses it on the onboarding form under the same rule, so it joins to the `participants` sheet. `null` only for sessions recorded before ID entry existed. |
| `session_id` | string | Unique **per device**, not globally (it is the start time in ms). Use `(user_id, session_id)` as the key. |
| `variant` | `"A"` \| `"B"` | **Required.** A = dimming only, B = baseline overlay only. Chosen by the participant on the home screen; each participant uses one version for the whole study, so this puts their sessions in the A or B group. The app also has `"C"` (both), hidden from participants (decision of 15 Oct 2026) — sessions with `C` come only from internal testing and are excluded from analysis. |
| `app_version` | string | Build name + number. |
| `session.*` | | Same values the app shows on its Summary screen. |
| `device.*` | | Needed because battery/temperature aren't comparable across phone models. |
| `detection.*` | number | Frame rates the session ran at. Constant today; recorded so a later change doesn't silently mix data. |
| `integrity.*` | | Result of the on-device check. Clean sessions are uploaded with `is_valid: true`. **Gap-only sessions are uploaded too** (decision of 15 Oct 2026): `is_valid` is `false` and `gap_count` says how many gaps — a gap is more than 2 s between two readings, usually Android throttling the app in the background. Any other failure (out-of-order or duplicate timestamps, missing timestamps, summary mismatch, empty session) is never uploaded. The server must accept `is_valid: false`; keep `gap_count` so analysis can exclude or adjust for gappy sessions. |
| `events[]` | array | One row **per second** for the whole session (a 60-min session ≈ 3,600 rows, ~90 KB). `status`: `0` = good, `1` = warning, `2` = bad. While PiP is closed (accelerometer-only mode) the status comes from the phone angle alone. |
| `device_metrics[]` | array | One row **every 15 s** (60 min ≈ 240 rows). `cpu_percent` is PostureGuard's own process only, normalised to 0–100 across all cores; `null` on the first row. `thermal_status`: `none`, `light`, `moderate`, `severe`, `critical`, `emergency`, `shutdown`, `unsupported`, `unknown`. `app_state`: `foreground`, `pip` (user in another app) or `background` (PiP closed — camera off, accelerometer-only mode). |
| `device_metrics_summary` | object | Computed on the phone from `device_metrics[]`. Redundant with it, but saves recomputing for every query. `battery_percent_per_hour` excludes charging intervals and is `null` under 1 min of discharge. |

---

## Differences from the plan's original field list

The plan lists: `user_id, session_id, timestamp, score, zone, streak, battery,
temperature, app_version` (+ `variant`). Against what the app actually records:

| Plan field | What the app has | Suggestion |
|---|---|---|
| `zone` | `status` 0/1/2 per second | Same thing — renamed `status` in `events[]`. |
| `score` | **Not stored per second.** Only the zone is logged; the 0–100 score is shown live but never saved. | **Decided 16 Oct 2026: not needed.** The zone per second and the session's `good_posture_percent` are enough. |
| `streak` | Derivable from `events[]` | Only the session's longest streak is sent (`session.longest_streak_seconds`). |
| `battery`, `temperature` | Every 15 s, not every second | Separate `device_metrics[]` table rather than columns on each event. |
| — | **New:** CPU %, thermal status, charging, screen, battery saver, app state | Needed for the Section 1 / resource-cost results. |
| `timestamp` | Epoch ms | `t` in the arrays. |

---

## Database tables

As built in `backend/app/models.py`. Identity (names, emails) is kept out of
all of these — see the plan's note on the restricted linking table.

```
sessions        (user_id, session_id, variant, app_version, device_id,
                 started_at, ended_at, duration_seconds, good_posture_percent,
                 longest_streak_seconds, worst_moment_timestamp,
                 manufacturer, device_model, android_version, cpu_cores,
                 foreground_fps, pip_fps, is_valid, gap_count, missing_count,
                 + every device_metrics_summary field (sample_count stored as
                   metrics_sample_count), received_at)
                 PRIMARY KEY (user_id, session_id)

posture_events  (user_id, session_id, t, status)
                 PRIMARY KEY (user_id, session_id, t)
device_metrics  (id, user_id, session_id, t, battery_percent,
                 battery_temperature_c, is_charging, thermal_status, cpu_percent,
                 is_screen_on, is_power_save, app_state)
```

`device_id` is the `X-Device-Id` header. `device_metrics_summary` is
flattened into `sessions`, so most analysis queries only touch one table.

## Server responses

| Case | Response |
|---|---|
| Clean or gap-only session | `200 {"ok": true}` |
| Same `(user_id, session_id)` again | `200 {"ok": true, "duplicate": true}` — first copy kept |
| Payload breaks a rule (bad `user_id` or `variant`, events out of order, `is_valid: false` without gaps, missing timestamps, no events) | `422` with the reason |

A `422` will never succeed on retry; see the note for the app below.

---

## Status in the app

The app builds and queues this payload now (`lib/services/upload_payload.dart`,
`lib/services/upload_service.dart`). Every field above is produced. Only the
server address is missing: until it is set, finished sessions wait in the
phone's `upload_queue` table and nothing is lost.

Today every session that fails the integrity check is marked `blocked` in the
queue and never sent, gaps included. Per the decision of 15 October 2026 this
changes: gap-only sessions will be sent with `is_valid: false`, and only the
other failures stay `blocked`. Not yet implemented in the app.

The app currently retries every non-2xx response. A `422` means the payload
itself is refused, so retrying it changes nothing: the app should mark such a
session `blocked` (keeping the server's message) instead of `pending`.
