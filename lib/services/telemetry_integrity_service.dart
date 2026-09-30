import '../models/integrity_report.dart';
import '../models/session_summary.dart';

/// Validates that a posture session's timestep sequence is complete and
/// continuous, before any of it is trusted or uploaded.
///
/// This class is intentionally pure: it takes plain maps in and returns a
/// report. It does not touch sqflite, the network, or Flutter, so it runs
/// under `flutter test` on the host with no device and no fixtures. The
/// database-backed entry points live in `telemetry_integrity_gate.dart`.
///
/// ## Note on the expected sampling rate
///
/// PostureGuard writes one `posture_events` row per second — see
/// `_startLogging()` in `session_screen.dart`, a `Timer.periodic` of 1s
/// calling `DatabaseService.logEvent`. The 2–5 FPS figure elsewhere in the
/// project is the ML Kit *inference* rate in `DetectionService.processFrame`,
/// which uses a drop-if-busy strategy and whose results are never persisted.
/// Hence [defaultExpectedInterval] is one second. Pass a smaller
/// `expectedInterval` if the logging cadence ever changes.
class TelemetryIntegrityService {
  /// Nominal spacing between persisted samples (the `_logTimer` period).
  static const Duration defaultExpectedInterval = Duration(seconds: 1);

  /// An interval counts as a gap once it exceeds
  /// `expectedInterval * gapTolerance`.
  ///
  /// Timestamps come from `DateTime.now()` inside an un-awaited timer
  /// callback, so a few tens of ms of drift per tick is normal and must not
  /// be flagged. 2.0 means "a whole sample was skipped".
  static const double defaultGapTolerance = 2.0;

  /// How far the stored `duration_seconds` may differ from the measured
  /// timestamp span before it is reported. Covers the `.round()` and the
  /// `.clamp(1, ...)` applied in `DatabaseService.endSession`.
  static const Duration defaultDurationTolerance = Duration(seconds: 2);

  /// How far `SessionSummary.date` may sit from the last recorded event.
  ///
  /// That field is assigned `DateTime.now()` when the session *ends*, after
  /// several awaited teardown steps, so it legitimately trails the final
  /// sample by a noticeable margin.
  static const Duration defaultEndTimeTolerance = Duration(seconds: 60);

  /// Fraction of the expected sample count that must actually be present
  /// before [IntegrityIssueType.sampleCountMismatch] is raised.
  static const double defaultSampleCountTolerance = 0.9;

  /// Validate one session's event sequence.
  ///
  /// [events] are rows as returned by `DatabaseService.getSessionEvents`, or
  /// the equivalent decoded from an upload payload. **Order matters**: they
  /// are validated in the order given, so pass them in *insertion* order to
  /// make clock rewinds visible (see `TelemetryIntegrityGate`).
  ///
  /// [summary] is optional. When supplied, the stored summary is cross-checked
  /// against the events it claims to describe, which catches truncated or
  /// partially deleted event data that the sequence alone looks fine for.
  static IntegrityReport validateSession({
    required String sessionId,
    required List<Map<String, dynamic>> events,
    SessionSummary? summary,
    Duration expectedInterval = defaultExpectedInterval,
    double gapTolerance = defaultGapTolerance,
    Duration durationTolerance = defaultDurationTolerance,
    Duration endTimeTolerance = defaultEndTimeTolerance,
    double sampleCountTolerance = defaultSampleCountTolerance,
    String timestampKey = 'timestamp',
  }) {
    if (expectedInterval.inMilliseconds <= 0) {
      throw ArgumentError.value(
        expectedInterval,
        'expectedInterval',
        'must be greater than zero',
      );
    }
    if (gapTolerance < 1.0) {
      throw ArgumentError.value(
        gapTolerance,
        'gapTolerance',
        'must be at least 1.0, otherwise every sample is a gap',
      );
    }

    final issues = <IntegrityIssue>[];
    final intervalMs = expectedInterval.inMilliseconds;
    final gapThresholdMs = intervalMs * gapTolerance;

    // ─── Pass 1: extract timestamps, recording the ones we cannot read ───

    var missingCount = 0;
    final timestamps = <int>[]; // readable timestamps, in the order given
    final sourceIndex = <int>[]; // their position in `events`

    for (var i = 0; i < events.length; i++) {
      final raw = events[i][timestampKey];
      final ts = _asEpochMs(raw);
      if (ts == null) {
        missingCount++;
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.missingTimestamp,
          message: raw == null
              ? 'Event at index $i has no "$timestampKey" value.'
              : 'Event at index $i has an unreadable "$timestampKey": $raw',
          index: i,
        ));
        continue;
      }
      timestamps.add(ts);
      sourceIndex.add(i);
    }

    if (events.isEmpty) {
      issues.add(const IntegrityIssue(
        type: IntegrityIssueType.emptySession,
        message: 'Session contains no events.',
      ));
      return IntegrityReport(
        sessionId: sessionId,
        isValid: false,
        issues: issues,
        gapCount: 0,
        missingCount: 0,
        outOfOrderCount: 0,
        sampleCount: 0,
      );
    }

    // ─── Pass 2: continuity and chronological order ───

    var gapCount = 0;
    var outOfOrderCount = 0;

    for (var i = 1; i < timestamps.length; i++) {
      final previous = timestamps[i - 1];
      final current = timestamps[i];
      final deltaMs = current - previous;
      final at = sourceIndex[i];

      if (deltaMs < 0) {
        outOfOrderCount++;
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.backwardJump,
          message: 'Timestamp at index $at goes backwards by '
              '${_readableMs(-deltaMs)} (from $previous to $current).',
          index: at,
          timestampMs: current,
        ));
        // Do not also test this interval for a gap: the sign is meaningless.
        continue;
      }

      if (deltaMs == 0) {
        outOfOrderCount++;
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.duplicateTimestamp,
          message:
              'Timestamp at index $at repeats the previous value ($current).',
          index: at,
          timestampMs: current,
        ));
        continue;
      }

      if (deltaMs > gapThresholdMs) {
        gapCount++;
        final missedSamples = (deltaMs / intervalMs).floor() - 1;
        issues.add(IntegrityIssue(
          type: IntegrityIssueType.gap,
          message: 'Gap of ${_readableMs(deltaMs)} before index $at '
              '(~$missedSamples sample${missedSamples == 1 ? '' : 's'} missing, '
              'expected ~${_readableMs(intervalMs)} spacing).',
          index: at,
          timestampMs: current,
        ));
      }
    }

    // ─── Pass 3: cross-check the stored summary against these events ───

    if (summary != null && timestamps.isNotEmpty) {
      issues.addAll(_checkSummaryConsistency(
        summary: summary,
        timestamps: timestamps,
        sampleCount: timestamps.length,
        intervalMs: intervalMs,
        durationTolerance: durationTolerance,
        endTimeTolerance: endTimeTolerance,
        sampleCountTolerance: sampleCountTolerance,
      ));
    }

    return IntegrityReport(
      sessionId: sessionId,
      isValid: issues.isEmpty,
      issues: issues,
      gapCount: gapCount,
      missingCount: missingCount,
      outOfOrderCount: outOfOrderCount,
      sampleCount: events.length,
    );
  }

  /// Compare the persisted `sessions` row with the `posture_events` it
  /// summarises. Disagreement means one of the two was altered or truncated
  /// after the fact.
  static List<IntegrityIssue> _checkSummaryConsistency({
    required SessionSummary summary,
    required List<int> timestamps,
    required int sampleCount,
    required int intervalMs,
    required Duration durationTolerance,
    required Duration endTimeTolerance,
    required double sampleCountTolerance,
  }) {
    final issues = <IntegrityIssue>[];

    // Use the extremes rather than first/last: if the sequence contains a
    // backward jump, position no longer implies chronology.
    final firstTs = timestamps.reduce((a, b) => a < b ? a : b);
    final lastTs = timestamps.reduce((a, b) => a > b ? a : b);
    final spanMs = lastTs - firstTs;

    // 1. Stored duration vs measured span.
    final storedDurationMs = summary.durationSeconds * 1000;
    final durationDeltaMs = (storedDurationMs - spanMs).abs();
    if (durationDeltaMs > durationTolerance.inMilliseconds) {
      issues.add(IntegrityIssue(
        type: IntegrityIssueType.durationMismatch,
        message: 'Summary claims ${summary.durationSeconds}s but the events '
            'span ${_readableMs(spanMs)} '
            '(off by ${_readableMs(durationDeltaMs)}).',
      ));
    }

    // 2. Sample count vs span. Valid because the logger is a fixed-period
    //    timer: a span of N intervals should carry N+1 samples.
    final expectedSamples = (spanMs / intervalMs).floor() + 1;
    final minimumSamples = (expectedSamples * sampleCountTolerance).floor();
    if (sampleCount < minimumSamples) {
      issues.add(IntegrityIssue(
        type: IntegrityIssueType.sampleCountMismatch,
        message: 'Only $sampleCount samples cover a span of '
            '${_readableMs(spanMs)}; ~$expectedSamples were expected at '
            '${_readableMs(intervalMs)} spacing.',
      ));
    }

    // 3. Summary end time vs last event. `SessionSummary.date` is stamped at
    //    session end (see DatabaseService.endSession), despite its name, so
    //    it is compared against the last sample and not the first.
    final endDeltaMs =
        (summary.date.millisecondsSinceEpoch - lastTs).abs();
    if (endDeltaMs > endTimeTolerance.inMilliseconds) {
      issues.add(IntegrityIssue(
        type: IntegrityIssueType.endTimeMismatch,
        message: 'Summary end time (${summary.date.toIso8601String()}) is '
            '${_readableMs(endDeltaMs)} away from the last recorded event.',
        timestampMs: lastTs,
      ));
    }

    // 4. The worst-moment marker must point inside the session it belongs to.
    final worstMs = summary.worstMomentTimestamp?.millisecondsSinceEpoch;
    if (worstMs != null && (worstMs < firstTs || worstMs > lastTs)) {
      issues.add(IntegrityIssue(
        type: IntegrityIssueType.markerOutOfRange,
        message: 'Worst-moment marker '
            '(${summary.worstMomentTimestamp!.toIso8601String()}) falls '
            'outside the recorded session window.',
        timestampMs: worstMs,
      ));
    }

    return issues;
  }

  /// Accept the int the schema guarantees, but tolerate the string/double/
  /// ISO-8601 forms a JSON payload may arrive in. Returns null if unreadable.
  static int? _asEpochMs(Object? raw) {
    if (raw == null) return null;
    if (raw is int) return raw;
    if (raw is double) return raw.isFinite ? raw.round() : null;
    if (raw is String) {
      final asInt = int.tryParse(raw);
      if (asInt != null) return asInt;
      return DateTime.tryParse(raw)?.millisecondsSinceEpoch;
    }
    if (raw is DateTime) return raw.millisecondsSinceEpoch;
    return null;
  }

  static String _readableMs(int ms) {
    if (ms < 1000) return '${ms}ms';
    final seconds = ms / 1000;
    if (seconds < 60) return '${seconds.toStringAsFixed(1)}s';
    final minutes = seconds ~/ 60;
    final remainder = (seconds % 60).round();
    return '${minutes}m ${remainder}s';
  }
}
