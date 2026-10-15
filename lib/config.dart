/// App-wide settings shared by the session screen and the upload payload.
class AppConfig {
  /// Study server base URL, e.g. `https://postureguard.example.org`.
  ///
  /// Set at build time so no URL is committed to the repo:
  ///   flutter run --release --dart-define=API_BASE_URL=https://...
  /// While empty, finished sessions stay queued on the phone and nothing is
  /// sent.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const String sessionsPath = '/api/sessions';

  /// Detection rates for live sessions, chosen from the Section 1 sweep
  /// (study/results/SECTION1_RESULTS.md).
  ///
  /// In PiP (the user is in another app, most of a session) the skeleton is
  /// tiny, so run at 3 FPS: 19.2% CPU vs 30.8% unthrottled (-38%), 2.5 °C
  /// cooler; 1-2 FPS saved under 1 more point. The ~18% floor is the camera
  /// stream itself, not inference.
  ///
  /// In the foreground the user is watching the skeleton, and 3 FPS looks
  /// laggy, so run at 15 FPS (28.6% CPU, ~11.8 FPS actually achieved).
  static const double foregroundDetectionFps = 15;
  static const double pipDetectionFps = 3;
}
