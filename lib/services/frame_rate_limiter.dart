/// Throttles a high-frequency callback (the camera image stream) down to a
/// target rate, by dropping frames that arrive before the next slot is due.
///
/// Used by [BenchmarkScreen] to run the detection pipeline at different
/// sampling rates for the Section 1 device benchmarks, and available to wire
/// into the live session once those benchmarks pick a production rate
/// (Section 2's 2-5 FPS throttling task).
class FrameRateLimiter {
  FrameRateLimiter(this.targetFps);

  /// Frames per second to allow through. Null or <= 0 means unlimited.
  final double? targetFps;

  DateTime? _last;
  int _passed = 0;

  /// Number of frames this limiter has let through since construction.
  int get passedCount => _passed;

  bool shouldProcess() {
    final fps = targetFps;
    if (fps == null || fps <= 0) {
      _passed++;
      return true;
    }
    final now = DateTime.now();
    final minGapUs = (1000000 / fps).round();
    if (_last == null || now.difference(_last!).inMicroseconds >= minGapUs) {
      _last = now;
      _passed++;
      return true;
    }
    return false;
  }
}
