import 'package:flutter_test/flutter_test.dart';
import 'package:postureguard/models/integrity_report.dart';
import 'package:postureguard/models/session_summary.dart';
import 'package:postureguard/services/telemetry_integrity_service.dart';

/// Which sessions the upload gate lets through (Decision 1, 15 Oct 2026):
/// clean ones, and ones whose only defects are gaps plus the sample
/// shortfall those gaps cause (`IntegrityReport.hasOnlyGapEffects`).

const int _t0 = 1700000000000;

/// Events at the given offsets (ms) from [_t0], in write order.
List<Map<String, dynamic>> _at(List<int> offsets) => [
      for (var i = 0; i < offsets.length; i++)
        <String, dynamic>{'id': i + 1, 'timestamp': _t0 + offsets[i], 'status': 0},
    ];

/// [count] samples at 1 Hz starting [startMs] after [_t0].
List<int> _run(int count, {int startMs = 0, int intervalMs = 1000}) =>
    [for (var i = 0; i < count; i++) startMs + i * intervalMs];

/// A summary consistent with [events], as `DatabaseService.endSession` builds it.
SessionSummary _summaryFor(List<Map<String, dynamic>> events) {
  final ts = events.map((e) => e['timestamp'] as int).toList();
  final first = ts.reduce((a, b) => a < b ? a : b);
  final last = ts.reduce((a, b) => a > b ? a : b);
  return SessionSummary(
    sessionId: 'session-a',
    date: DateTime.fromMillisecondsSinceEpoch(last),
    durationSeconds: ((last - first) / 1000).round(),
    goodPosturePercent: 100,
    longestStreakSeconds: events.length,
  );
}

IntegrityReport _check(List<Map<String, dynamic>> events) =>
    TelemetryIntegrityService.validateSession(
      sessionId: 'session-a',
      events: events,
      summary: _summaryFor(events),
    );

/// The gate's rule, as written in `TelemetryIntegrityGate.buildUploadPayload`.
bool _uploads(IntegrityReport r) => r.isValid || r.hasOnlyGapEffects;

Iterable<IntegrityIssueType> _types(IntegrityReport r) =>
    r.issues.map((i) => i.type);

void main() {
  test('a clean session uploads as valid', () {
    final report = _check(_at(_run(60)));

    expect(report.isValid, isTrue, reason: report.toString());
    expect(report.hasOnlyGapEffects, isFalse);
    expect(_uploads(report), isTrue);
  });

  test('a session with a short gap uploads with its gap count', () {
    // 30 s, a 3 s hole, 30 s more: a few seconds lost to throttling.
    final report = _check(_at([..._run(30), ..._run(30, startMs: 32000)]));

    expect(report.isValid, isFalse);
    expect(_types(report), everyElement(IntegrityIssueType.gap));
    expect(report.gapCount, 1);
    expect(report.hasOnlyGaps, isTrue);
    expect(report.hasOnlyGapEffects, isTrue);
    expect(_uploads(report), isTrue);
  });

  test('a long gap that also causes a sample shortfall still uploads', () {
    // 10 s, a 60 s hole, 10 s more: far fewer samples than the span implies.
    final report = _check(_at([..._run(10), ..._run(10, startMs: 69000)]));

    expect(_types(report), contains(IntegrityIssueType.gap));
    expect(_types(report), contains(IntegrityIssueType.sampleCountMismatch));
    expect(report.hasOnlyGaps, isFalse);
    expect(report.hasOnlyGapEffects, isTrue);
    expect(report.gapCount, greaterThan(0));
    expect(_uploads(report), isTrue);
  });

  test('a sample shortfall without any gap is blocked', () {
    // Spacing of 1.9 s stays under the 2 s gap threshold but leaves too few
    // samples for the span: not explained by gaps, so not trusted.
    final report = _check(_at(_run(20, intervalMs: 1900)));

    expect(report.gapCount, 0);
    expect(_types(report), contains(IntegrityIssueType.sampleCountMismatch));
    expect(report.hasOnlyGapEffects, isFalse);
    expect(_uploads(report), isFalse);
  });

  test('gaps plus a backward clock jump are blocked', () {
    final report = _check(_at([
      ..._run(10),
      ..._run(10, startMs: 15000), // gap
      12000, // goes backwards
    ]));

    expect(_types(report), contains(IntegrityIssueType.gap));
    expect(_types(report), contains(IntegrityIssueType.backwardJump));
    expect(report.hasOnlyGapEffects, isFalse);
    expect(_uploads(report), isFalse);
  });

  test('gaps plus a duplicate timestamp are blocked', () {
    final report = _check(_at([
      ..._run(10),
      ..._run(10, startMs: 15000), // gap
      24000, // repeats the last one
    ]));

    expect(_types(report), contains(IntegrityIssueType.duplicateTimestamp));
    expect(report.hasOnlyGapEffects, isFalse);
    expect(_uploads(report), isFalse);
  });

  test('an empty session is blocked', () {
    final report = TelemetryIntegrityService.validateSession(
      sessionId: 'session-a',
      events: const [],
    );

    expect(report.hasOnlyGapEffects, isFalse);
    expect(_uploads(report), isFalse);
  });
}
