# Section 1 — Device resource benchmarks

CPU, battery and temperature cost of PostureGuard on one Android phone, measured
September 2026 by Marthe. Two parts: a controlled frame-rate sweep that chose
the production detection rate, and five real-use runs of the app at that rate.

Raw data: `study/results/session_metrics/` — one CSV per run (a reading every
15 s) plus `section1_runs_summary.csv` (one row per run).

---

## Key findings

1. **Throttling detection from ~19 FPS to 3 FPS cut PostureGuard's CPU use by
   38% (30.8% → 19.2%) and ran 2.5 °C cooler.** Below 3 FPS the saving is
   under one percentage point; the remaining ~18% is the camera stream itself,
   not pose inference.
2. **In real use, PostureGuard in picture-in-picture uses 11–15% CPU**, flat
   over a full hour.
3. **Closing PiP (accelerometer-only mode) drops the app's CPU to 1–2%.**
   Nearly all of the app's cost is the camera and pose detection; tilt
   monitoring is close to free.
4. **With the camera running and the phone otherwise idle, the device never
   throttled** (max 38.9 °C over 60 min). Moderate thermal throttling appeared
   only when combined with heavy use of other apps.
5. **Whole-device battery drain was 13.7 %/hr with PostureGuard running on an
   idle phone** (screen kept on by the app), and 17.6–21 %/hr during normal
   phone use.

---

## Part 1 — Frame-rate sweep

**Setup:** automated benchmark (`integration_test/device_benchmark_test.dart`,
run with `flutter drive`), 10 minutes per rate, app in the foreground, phone
not otherwise used, not charging. Debug build.

| Target FPS | Achieved FPS | Avg CPU | Avg temp |
|---:|---:|---:|---:|
| 1 | 0.98 | 18.2% | 35.3 °C |
| 2 | 1.94 | 18.7% | 36.0 °C |
| **3** | **2.84** | **19.2%** | **36.7 °C** |
| 5 | 4.57 | 22.3% | 37.0 °C |
| 10 | 8.35 | 30.8% | 38.2 °C |
| 15 | 11.75 | 28.6% | 38.5 °C |
| 30 (≈ unthrottled) | 18.69 | 30.8% | 39.2 °C |

- The pipeline tops out at ~19 FPS: pose detection, not the camera, is the
  bottleneck, so "30" is effectively unthrottled.
- Battery per rate is not reported: Android reports whole percent only, which
  is too coarse over 10 minutes.

**Decision:** 3 FPS while in PiP (most of a session), 15 FPS while the app is
full-screen, where the user watches the skeleton and 3 FPS looked laggy.

---

## Part 2 — Real-use runs

**Setup:** release build, detection at 3 FPS in PiP / 15 FPS full-screen. Phone
unplugged, Wi-Fi on, battery saver off, same brightness in every run, wireless
debugging off. The app keeps the screen on for the whole session. Metrics
sampled every 15 s by the app itself.

| Run | Length | PiP | Other apps | Battery | Drain | App CPU avg / max | Temp start → max | Throttling |
|---|---|---|---|---|---|---|---|---|
| A | 30 min | open | yes | 49 → 40% | 17.6 %/hr | 12.9 / 18.2% | 33.7 → 40.2 °C | light |
| B | 60 min | open | yes | 80 → 59% | 21.0 %/hr | 11.1 / 24.3%¹ | 30.6 → 43.6 °C | moderate |
| C | 60 min | open | no | 76 → 62% | 13.7 %/hr | 15.1 / 17.4% | 35.7 → 38.9 °C | none |
| D | 60 min | closed | no | 60 → 55% | 5.2 %/hr² | 1.7 / 9.5% | 33.2 → 34.9 °C | none |
| E | 60 min | closed | yes | 47 → 41% | 6.0 %/hr² | 1.3 / 10.2% | 30.6 → 33.3 °C | none |

¹ Peak recorded in the final minute when the app was opened full-screen
(15 FPS) to end the session; in PiP the run stayed at 8–16%.
² Screen was dimmed for much of the run — see limitations.

### Temperature over time

- **Run B (camera + apps):** 30.6 → 39.3 °C in the first 8 min ("light"),
  42 °C by 22 min ("moderate"), then steady at 41.4–43.6 °C for the remaining
  38 min. It plateaued rather than climbing.
- **Run C (camera, idle):** +2.3 °C in the first 15 min, then +1 °C over the
  next 45. No throttling, despite starting 5 °C warmer than run B.
- **Runs D and E (camera off):** the phone cooled or stayed flat.

Runs B and C used the same app settings, so the difference in heat between
them comes from the user's other apps, not from PostureGuard.

---

## Limitations — state these in the paper

- **One device.** A single Android phone (10 CPU cores). Numbers will differ on
  other hardware; the study records phone model per participant for this
  reason.
- **CPU is PostureGuard's own process only**, normalised to 0–100% across all
  cores. Android doesn't let apps read system-wide CPU. Battery and
  temperature are whole-device and include the screen and any other apps.
- **Battery drain depends heavily on the screen.** The app keeps the screen on
  during a session, and the dimming feedback lowers brightness while posture
  or phone angle is bad. In runs D and E the screen was dimmed for much of the
  hour, so their low drain is mainly a dark screen, not only the camera being
  off. Compare modes on **CPU**, not battery.
- **All five runs used the build before the feedback modes were split**, where
  dimming and the baseline overlay were both active — equivalent to today's
  variant C ("Both"). Detection and logging are identical in A, B and C, so
  the CPU and temperature results hold for all three; battery can differ
  slightly, since B never dims the screen.
- **The sweep ran as a debug build; the real-use runs as release.** The
  comparison between frame rates holds, but the sweep's absolute CPU figures
  are higher than a release build would show (release in PiP: 11–15% vs
  19.2% in the sweep).
- **Idle CPU was higher than in-use CPU** (run C 15.1% vs run B 11.0%) for the
  same work. The likely cause is CPU frequency scaling: an idle phone runs its
  cores slower, so each frame takes a larger share of time. In run C, CPU also
  crept from ~11% to ~17% over the hour, which run B did not show. Not
  explained by these data.
- **Battery resolution is 1%**, so drain rates from the 30-minute run are
  approximate (±2 %/hr).
- **Uncontrolled conditions:** runs were at different times of day, with
  different room temperatures and different start battery levels.

---

## Suggested paper text

> We measured PostureGuard's resource use on an Android smartphone. Throttling
> pose detection from its unconstrained rate (~19 FPS) to 3 FPS reduced the
> app's CPU usage by 38% (30.8% → 19.2%) and lowered battery temperature by
> 2.5 °C; lower rates yielded no meaningful further saving, as the remaining
> load was the camera stream itself. The deployed configuration runs detection
> at 3 FPS while the app is minimised to picture-in-picture and at 15 FPS when
> full-screen. In hour-long sessions of normal phone use, PostureGuard's own
> process used 11–15% CPU with no upward trend. Running on an otherwise idle
> phone, the device reached 38.9 °C with no thermal throttling; whole-device
> battery drain was 13.7 %/hr, including the screen, which the app keeps on
> during a session. When the user closes the picture-in-picture window,
> monitoring continues from the accelerometer alone and the app's CPU usage
> falls to 1–2%.
