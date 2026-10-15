class SessionSummary {
  final int? id;
  final String sessionId;
  final DateTime date;
  final int durationSeconds;
  final double goodPosturePercent;
  final int longestStreakSeconds;
  final DateTime? worstMomentTimestamp;

  /// Feedback variant code (`A` or `B`). Null for sessions recorded before
  /// variants existed.
  final String? variant;

  /// Participant ID (`PG-XXXX-XXXX`). Null for sessions recorded before IDs
  /// were entered in the app.
  final String? userId;

  const SessionSummary({
    this.id,
    required this.sessionId,
    required this.date,
    required this.durationSeconds,
    required this.goodPosturePercent,
    required this.longestStreakSeconds,
    this.worstMomentTimestamp,
    this.variant,
    this.userId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'session_id': sessionId,
        'date': date.toIso8601String(),
        'duration_seconds': durationSeconds,
        'good_posture_percent': goodPosturePercent,
        'longest_streak': longestStreakSeconds,
        'worst_moment_timestamp':
            worstMomentTimestamp?.millisecondsSinceEpoch,
        'variant': variant,
        'user_id': userId,
      };

  factory SessionSummary.fromMap(Map<String, dynamic> map) => SessionSummary(
        id: map['id'] as int?,
        sessionId: map['session_id'] as String,
        date: DateTime.parse(map['date'] as String),
        durationSeconds: map['duration_seconds'] as int,
        goodPosturePercent: (map['good_posture_percent'] as num).toDouble(),
        longestStreakSeconds: map['longest_streak'] as int,
        worstMomentTimestamp: map['worst_moment_timestamp'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                map['worst_moment_timestamp'] as int)
            : null,
        variant: map['variant'] as String?,
        userId: map['user_id'] as String?,
      );

  String get formattedDuration {
    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;
    return '${minutes}m ${seconds}s';
  }
}
