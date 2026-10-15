# PostureGuard

Real-time posture monitor for Android. Uses the front camera and accelerometer together to detect poor posture and alert you with screen-dimming or baseline-overlay feedback — no wearables, no subscriptions. Built for a research study comparing the two feedback types: see [`study/PROJECT_PLAN.md`](study/PROJECT_PLAN.md).

---

## How it works

Place your phone in front of you (propped up or held). PostureGuard uses Google ML Kit to track 5 skeletal landmarks in every camera frame — nose, both ears, both shoulders. It computes a Nose-to-Shoulder (NTS) ratio that is scale-invariant and resolution-independent, then compares it against a personal baseline captured during calibration.

The accelerometer runs in parallel. The gravity vector at calibration time is stored alongside the camera baseline. During a session, the signed pitch angle between the two vectors is used to confirm or independently trigger phone-position violations — this handles the common case where shoulders drift off-screen and the camera alone becomes unreliable.

### Calibration

When you start a session for the first time, you sit in good posture for 5 seconds. The app:

- Collects multiple frames and averages landmark positions into one stable baseline
- Normalises all coordinates to 0–1 (so the baseline is device-resolution independent)
- Records the gravity vector (X, Y, Z) as the phone-angle baseline
- Derives personalised thresholds for shoulder and head-tilt detection from the standard deviation across the captured samples
- Persists everything to SharedPreferences — the baseline survives app restarts

### Detected violations

| Violation | Signal |
|-----------|--------|
| Phone too high | NTS drops + gravity pitch (nose appears lower in frame) |
| Phone too low | NTS rises + gravity pitch (nose appears higher in frame) |
| Head tilt | Ear-height difference vs. baseline |
| Shoulder asymmetry | Per-shoulder Y delta vs. baseline |
| Shoulder rounding | Shoulder width narrowing vs. baseline |

Phone-position violations suppress all body checks while active. Perspective distortion at extreme angles makes shoulder and head readings unreliable, so they are ignored until the phone returns to a normal position. A soft zone (35% of the hard threshold) begins suppressing shoulder checks even before a hard violation fires.

### Scoring

Every frame produces an overall score (0–100 %) averaged from seven per-metric scores. A 30-frame rolling window smooths the score for the UI. EMA smoothing (α = 0.25) on the NTS value prevents single noisy frames from flipping the phone-position state. All violations use entry/exit hysteresis bands (65% exit threshold) to eliminate per-frame flickering.

| Score | Label |
|-------|-------|
| ≥ 90 % | Excellent Posture |
| 75–89 % | Good Posture |
| 60–74 % | Slight Adjustment Needed |
| 40–59 % | Needs Improvement |
| 20–39 % | Poor Posture |
| < 20 % | Critical — Fix Now |


### Feedback variants

Three buttons on the home screen choose the feedback. No session starts until one is chosen, and every session records which one was active.

| Variant | Feedback |
|---------|----------|
| **A — Dimming** | Screen dims |
| **B — Baseline** | Ghost of your calibrated posture drawn over other apps |
| **C — Both** | Dimming and the ghost overlay together |

Feedback fires when posture stays bad (score below 50 %) for 5 seconds while the app is in picture-in-picture, or when the phone angle stays bad for 5 seconds. Dimming uses the system brightness API: brightness steps down by 10 per 200 ms to a floor of 5, and is fully restored as soon as posture corrects. Voice alerts, vibration and the coloured border are the same in all three variants.

### Participant ID

Before the first session the app asks for a participant ID: at least 6 letters/numbers, stored exactly as typed (case-sensitive). Participants choose it on the onboarding form ([`study/participant_onboarding.html`](study/participant_onboarding.html)), and every session is tagged with it.

---

## Features

- **Personal calibration** — your own posture and phone angle are the baseline, not a generic model
- **Real-time skeleton overlay** — live pose drawn on the camera preview alongside your ghost baseline
- **Ambient border** — full-screen colour border: green (≥ 80) → orange (50–79) → red (< 50)
- **Early-warning badges** — soft Head Rise / Head Drop indicators fire before a hard violation triggers
- **Rule chips** — per-metric colour chips (Shoulders · Head Tilt · Hunching) hidden when phone position is bad
- **Good-posture streak** — consecutive seconds at ≥ 80 %, displayed as a live counter and logged per session
- **Three feedback variants** — dimming (A), baseline overlay (B), or both (C), chosen on the home screen
- **Screen dimming** via system brightness API (not an overlay tint)
- **Ghost skeleton overlay** — draws your baseline skeleton on top of any app via `SYSTEM_ALERT_WINDOW`, 5 s after bad posture starts
- **Picture-in-Picture (PiP)** — compact floating window; monitoring continues while you use other apps
- **Accelerometer-only mode** — close PiP entirely and the accelerometer keeps monitoring phone tilt in the background with no camera needed
- **Frame-rate throttling** — pose detection runs at 3 FPS in PiP and 15 FPS full-screen (see [`study/results/SECTION1_RESULTS.md`](study/results/SECTION1_RESULTS.md))
- **Android Foreground Service** — OS cannot kill the monitoring process; a notification keeps it alive
- **Session history** stored locally in SQLite — per-second posture log, overall score, time in each zone, longest streak
- **Device metrics** — battery, temperature, CPU and thermal status sampled every 15 s during each session
- **Telemetry integrity check** — every session is checked for gaps and missing or out-of-order timestamps before upload; failing sessions stay on the phone
- **Study upload** — finished sessions are queued and sent to the study server, retried when offline
- **Session charts** rendered with fl_chart
- **Dark mode** support throughout
- **No account, no ads, no analytics**

---

## Requirements

- **Android 8.0+ (API 26+)** for the study. The build installs from Android 7.0 (API 24, Flutter's default `minSdk`), but picture-in-picture on phones — and with it feedback while using other apps — needs Android 8.0
- Front-facing camera
- The following permissions are requested at runtime:
  - `CAMERA`
  - `POST_NOTIFICATIONS` (foreground service notification)
  - `SYSTEM_ALERT_WINDOW` (ghost overlay over other apps)
  - `WRITE_SETTINGS` (system brightness control)

---

## Setup

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) 3.x
- Android Studio or VS Code with the Flutter extension
- An Android device or emulator (API 26+)

### Install

```bash
git clone <repo-url>
cd PostureGuard
flutter pub get
```

Or use the automated setup script (installs Flutter via Homebrew if missing, writes config files, checks permissions):

```bash
bash setup.sh
```

### Run

Connect an Android device via USB with developer mode and USB debugging enabled, then:

```bash
flutter run
```

Sessions are uploaded only when the study server address is set at build time:

```bash
flutter run --release --dart-define=API_BASE_URL=https://your-server
```

Without it, finished sessions stay queued on the phone and nothing is sent.

### Build release APK

```bash
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

---

## Project structure

```
lib/
├── main.dart                     # App entry point, background service init
├── config.dart                   # Server URL (--dart-define) and detection frame rates
├── background_service.dart       # Android foreground service setup
│
├── models/
│   ├── calibration_data.dart     # Stored baseline landmarks + accel vector + thresholds
│   ├── posture_status.dart       # good / warning / bad enum + score → status mapping
│   ├── session_summary.dart      # Per-session stats model (incl. user_id, variant)
│   ├── feedback_variant.dart     # A — Dimming / B — Baseline / C — Both
│   ├── integrity_report.dart     # Telemetry integrity check result
│   └── device_metrics_summary.dart # Per-session battery / CPU / temperature summary
│
├── services/
│   ├── camera_service.dart       # CameraX controller (NV21 format)
│   ├── detection_service.dart    # ML Kit pose detection + landmark normalisation
│   ├── frame_rate_limiter.dart   # Drops camera frames down to a target FPS
│   ├── posture_analyzer.dart     # NTS ratio, accel pitch diff, 7-violation detection, hysteresis
│   ├── feedback_service.dart     # TTS alerts, vibration, 30-frame score window, streak tracking
│   ├── calibration_service.dart  # 5-second baseline capture, threshold derivation, persistence
│   ├── movement_service.dart     # Accelerometer EMA smoothing
│   ├── overlay_service.dart      # Native overlay channel (SYSTEM_ALERT_WINDOW)
│   ├── window_state_service.dart # Foreground / PiP / background state from MainActivity
│   ├── participant_service.dart  # Participant ID rule and storage
│   ├── variant_service.dart      # Selected feedback variant
│   ├── device_metrics_service.dart   # One battery / CPU / thermal reading
│   ├── session_metrics_recorder.dart # Samples device metrics every 15 s during a session
│   ├── benchmark_runner.dart     # Frame-rate sweep for the Section 1 benchmarks
│   ├── telemetry_integrity_service.dart # Pure validator: gaps, missing / out-of-order timestamps
│   ├── telemetry_integrity_gate.dart    # Runs the validator before any upload
│   ├── upload_payload.dart       # Builds the body defined in study/API_SCHEMA.md
│   ├── upload_service.dart       # Upload queue, HTTPS POST, retries
│   └── database_service.dart     # SQLite: sessions, events, device metrics, upload queue
│
├── screens/
│   ├── home_screen.dart          # Participant ID, feedback variant, last session, navigation
│   ├── calibration_screen.dart   # 5-second baseline capture UI
│   ├── session_screen.dart       # Live monitoring — HUD, score, chips, feedback
│   ├── summary_screen.dart       # End-of-session results
│   └── history_screen.dart       # Past sessions with charts
│
└── widgets/
    ├── camera_preview.dart
    ├── skeleton_overlay.dart     # Live pose + ghost baseline drawn on camera feed
    ├── ambient_border.dart       # Full-screen colour border
    ├── score_meter.dart          # Animated 0–100 % bar
    ├── baseline_overlay.dart     # Teal pulsing ghost guide (any app)
    └── heatmap_chart.dart

android/
└── app/src/main/kotlin/com/postureguard/postureguard/
    ├── MainActivity.kt
    └── OverlayService.kt         # Native foreground overlay service

test/                             # Unit tests (integrity check, payload, metrics, participant ID)
integration_test/                 # On-device frame-rate benchmark
study/                            # Study plan, API schema, onboarding form + backend, results
```

---

## Dependencies

| Package | Purpose |
|---------|---------|
| `google_mlkit_pose_detection` | On-device skeleton landmark detection |
| `camera` | Camera preview and frame stream (CameraX / NV21) |
| `sensors_plus` | Accelerometer data |
| `flutter_background_service` | Android foreground service |
| `flutter_local_notifications` | Foreground service notification channel |
| `sqflite` | Local session history database |
| `fl_chart` | Session history charts |
| `permission_handler` | Runtime permission requests |
| `wakelock_plus` | Keep screen on during sessions |
| `shared_preferences` | Calibration baseline, participant ID and variant persistence |
| `http` | Session upload to the study server |
| `path_provider` | CSV output location for benchmarks and session metrics |

---

## Privacy

Camera frames are processed on the phone and never stored or uploaded. Sessions are stored in SQLite on the phone; when a study server address is set at build time, each finished session is uploaded to it: the participant ID, feedback variant, per-second posture zones, session summary, device metrics and phone model. The full field list is in [`study/API_SCHEMA.md`](study/API_SCHEMA.md), and participants agree to it on the onboarding form. Without a server address nothing leaves the phone. There is no account, and no ads or analytics.
