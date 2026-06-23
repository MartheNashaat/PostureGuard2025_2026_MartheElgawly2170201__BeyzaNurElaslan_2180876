# PostureGuard

Real-time posture monitor for Android. Uses the front camera and accelerometer together to detect poor posture and alert you with screen-dimming feedback — no wearables, no subscriptions, no cloud.

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


### Screen dimming

When score stays below 50 % for 5 seconds, the app dims the phone display itself using the system brightness API. Brightness steps down by 10 per 200 ms to a floor of 5. It is fully restored as soon as posture corrects.

---

## Features

- **Personal calibration** — your own posture and phone angle are the baseline, not a generic model
- **Real-time skeleton overlay** — live pose drawn on the camera preview alongside your ghost baseline
- **Ambient border** — full-screen colour border: green (≥ 80) → orange (50–79) → red (< 50)
- **Early-warning badges** — soft Head Rise / Head Drop indicators fire before a hard violation triggers
- **Rule chips** — per-metric colour chips (Shoulders · Head Tilt · Hunching) hidden when phone position is bad
- **Good-posture streak** — consecutive seconds at ≥ 80 %, displayed as a live counter and logged per session
- **Screen dimming** via system brightness API (not an overlay tint)
- **Ghost skeleton overlay** — draws your baseline skeleton on top of any app via `SYSTEM_ALERT_WINDOW`, 5 s after bad posture starts
- **Picture-in-Picture (PiP)** — compact floating window; monitoring continues while you use other apps
- **Accelerometer-only mode** — close PiP entirely and the accelerometer keeps monitoring phone tilt in the background with no camera needed
- **Android Foreground Service** — OS cannot kill the monitoring process; a notification keeps it alive
- **Session history** stored locally in SQLite — per-second posture log, overall score, time in each zone, longest streak
- **Session charts** rendered with fl_chart
- **Dark mode** support throughout
- **No cloud, no account, no tracking** — all data stays on device

---

## Requirements

- **Android 5.0+ (API 21+)**
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
- An Android device or emulator (API 21+)

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
├── background_service.dart       # Android foreground service setup
│
├── models/
│   ├── calibration_data.dart     # Stored baseline landmarks + accel vector + thresholds
│   ├── posture_status.dart       # good / warning / bad enum + score → status mapping
│   └── session_summary.dart      # Per-session stats model
│
├── services/
│   ├── camera_service.dart       # CameraX controller (NV21 format)
│   ├── detection_service.dart    # ML Kit pose detection + landmark normalisation
│   ├── posture_analyzer.dart     # NTS ratio, accel pitch diff, 7-violation detection, hysteresis
│   ├── feedback_service.dart     # TTS alerts, vibration, 30-frame score window, streak tracking
│   ├── calibration_service.dart  # 5-second baseline capture, threshold derivation, persistence
│   ├── movement_service.dart     # Accelerometer EMA smoothing
│   ├── overlay_service.dart      # Native overlay channel (SYSTEM_ALERT_WINDOW)
│   └── database_service.dart     # SQLite session persistence
│
├── screens/
│   ├── home_screen.dart          # Last session summary + navigation
│   ├── calibration_screen.dart   # 5-second baseline capture UI
│   ├── session_screen.dart       # Live monitoring — HUD, score, chips, dimming
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
| `vibration` | Haptic feedback |
| `sqflite` | Local session history database |
| `fl_chart` | Session history charts |
| `permission_handler` | Runtime permission requests |
| `wakelock_plus` | Keep screen on during sessions |
| `shared_preferences` | Calibration baseline persistence |

---

## Privacy

All data is stored on-device. PostureGuard does not connect to the internet, does not require an account, and does not include ads or analytics.
