/// Result types for the pre-upload telemetry integrity check.
///
/// Deliberately free of any Flutter or sqflite import so the validator that
/// produces these can be unit-tested on the host VM with no device binding.
library;

/// What kind of defect was found in a session's timestep sequence.
enum IntegrityIssueType {
  /// The session contains no events at all.
  emptySession,

  /// An event row had a null, absent, or non-numeric timestamp.
  missingTimestamp,

  /// The interval between two consecutive samples exceeded the allowed
  /// multiple of the expected sampling interval.
  gap,

  /// A sample's timestamp is earlier than its predecessor's (clock rewind).
  backwardJump,

  /// Two consecutive samples share the same timestamp.
  duplicateTimestamp,

  /// The stored summary duration disagrees with the event timestamp span.
  durationMismatch,

  /// Far fewer samples than the timestamp span implies at the expected rate.
  sampleCountMismatch,

  /// The stored summary end time is far from the last recorded event.
  endTimeMismatch,

  /// The summary's worst-moment marker falls outside the session's own span.
  markerOutOfRange,
}

/// One defect, carrying enough context to locate it in the raw event list.
class IntegrityIssue {
  final IntegrityIssueType type;
  final String message;

  /// Index into the event list the issue was found at, when applicable.
  final int? index;

  /// Timestamp (ms since epoch) the issue was found at, when applicable.
  final int? timestampMs;

  const IntegrityIssue({
    required this.type,
    required this.message,
    this.index,
    this.timestampMs,
  });

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'message': message,
        if (index != null) 'index': index,
        if (timestampMs != null) 'timestamp': timestampMs,
      };

  @override
  String toString() => '[${type.name}] $message';
}

/// Verdict for a single session.
///
/// [isValid] is true only when [issues] is empty. The counters are always
/// populated, so a caller can distinguish "one skipped sample" from
/// "half the session is missing" without parsing messages.
class IntegrityReport {
  final String sessionId;
  final bool isValid;
  final List<IntegrityIssue> issues;

  /// Number of intervals that exceeded the allowed gap threshold.
  final int gapCount;

  /// Number of event rows whose timestamp was null, absent, or non-numeric.
  final int missingCount;

  /// Number of intervals that broke strict chronological order
  /// (backward jumps and duplicate timestamps).
  final int outOfOrderCount;

  /// Number of event rows examined, including those with bad timestamps.
  final int sampleCount;

  const IntegrityReport({
    required this.sessionId,
    required this.isValid,
    required this.issues,
    required this.gapCount,
    required this.missingCount,
    required this.outOfOrderCount,
    required this.sampleCount,
  });

  /// Convenience constructor for a session with nothing wrong with it.
  factory IntegrityReport.clean({
    required String sessionId,
    required int sampleCount,
  }) =>
      IntegrityReport(
        sessionId: sessionId,
        isValid: true,
        issues: const [],
        gapCount: 0,
        missingCount: 0,
        outOfOrderCount: 0,
        sampleCount: sampleCount,
      );

  /// True when the session has defects but none that destroy its meaning —
  /// useful if you later want to upload-with-a-flag instead of holding back.
  bool get hasOnlyGaps =>
      !isValid && issues.every((i) => i.type == IntegrityIssueType.gap);

  /// Serializable form, for embedding in an upload envelope or a local log.
  Map<String, dynamic> toMap() => {
        'session_id': sessionId,
        'is_valid': isValid,
        'gap_count': gapCount,
        'missing_count': missingCount,
        'out_of_order_count': outOfOrderCount,
        'sample_count': sampleCount,
        'issues': issues.map((i) => i.toMap()).toList(),
      };

  @override
  String toString() {
    if (isValid) {
      return 'IntegrityReport($sessionId: valid, $sampleCount samples)';
    }
    return 'IntegrityReport($sessionId: INVALID, ${issues.length} issues, '
        'gaps=$gapCount missing=$missingCount outOfOrder=$outOfOrderCount)';
  }
}
