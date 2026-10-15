import 'package:flutter_test/flutter_test.dart';
import 'package:postureguard/models/integrity_report.dart';
import 'package:postureguard/models/session_summary.dart';
import 'package:postureguard/services/telemetry_integrity_service.dart';

/// Fixed epoch so failures print stable, comparable numbers.
const int _t0 = 1700000000000; // 2023-11-14T22:13:20Z

/// Build a run of samples spaced [intervalMs] apart, as
/// `DatabaseService.getSessionEvents` would return them.
List<Map<String, dynamic>> _events(
  int count, {
  int startMs = _t0,
  int intervalMs = 1000,
  int status = 0,
}) =>
    List.generate(count, (i) {
      return <String, dynamic>{
        'id': i + 1,
        'session_id': 'session-a',
        'timestamp': startMs + (i * intervalMs),
        'status': status,
      };
    });

/// A summary consistent with [events], as `endSession` would compute it.
SessionSummary _summaryFor(List<Map<String, dynamic>> events) {
  final first = events.first['timestamp'] as int;
  final last = events.last['timestamp'] as int;
  return SessionSummary(
    sessionId: 'session-a',
    date: DateTime.fromMillisecondsSinceEpoch(last),
    durationSeconds: ((last - first) / 1000).round(),
    goodPosturePercent: 100,
    longestStreakSeconds: events.length,
  );
}

Iterable<IntegrityIssueType> _types(IntegrityReport r) =>
    r.issues.map((i) => i.type);

void main() {
  group('complete session', () {
    test('a clean 60-sample run at 1Hz is valid', () {
      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: _events(60),
      );

      expect(report.isValid, isTrue);
      expect(report.issues, isEmpty);
      expect(report.gapCount, 0);
      expect(report.missingCount, 0);
      expect(report.outOfOrderCount, 0);
      expect(report.sampleCount, 60);
    });

    test('normal timer jitter is not reported as a gap', () {
      // Timer.periodic drifts and the insert is async: real spacing wobbles
      // by tens of ms around 1000. None of this is a defect.
      final jitter = [0, 1012, 1987, 3040, 3996, 5050, 6010];
      final events = [
        for (var i = 0; i < jitter.length; i++)
          <String, dynamic>{'id': i + 1, 'timestamp': _t0 + jitter[i], 'status': 0},
      ];

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.isValid, isTrue, reason: report.toString());
      expect(report.gapCount, 0);
    });

    test('a clean run cross-checks against its own summary', () {
      final events = _events(31);
      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
        summary: _summaryFor(events),
      );

      expect(report.isValid, isTrue, reason: report.toString());
    });

    test('a single sample has no intervals to fault', () {
      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: _events(1),
      );

      expect(report.isValid, isTrue);
      expect(report.sampleCount, 1);
    });
  });

  group('session with a gap in the middle', () {
    test('a 10s hole is detected and located', () {
      // 10 samples, then a 10-second hole, then 10 more.
      final events = [
        ..._events(10),
        ..._events(10, startMs: _t0 + 19000),
      ];

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.isValid, isFalse);
      expect(report.gapCount, 1);
      expect(report.missingCount, 0);
      expect(report.outOfOrderCount, 0);
      expect(_types(report), everyElement(IntegrityIssueType.gap));

      final gap = report.issues.single;
      expect(gap.index, 10, reason: 'gap is reported at the sample after it');
      expect(gap.timestampMs, _t0 + 19000);
      expect(gap.message, contains('10.0s'));
      expect(gap.message, contains('~9 samples missing'));
    });

    test('multiple holes are counted separately', () {
      final events = [
        ..._events(5),
        ..._events(5, startMs: _t0 + 9000),
        ..._events(5, startMs: _t0 + 20000),
      ];

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.gapCount, 2);
      expect(report.isValid, isFalse);
    });

    test('gap threshold is exclusive at exactly interval * tolerance', () {
      // Default tolerance 2.0 => 2000ms is allowed, 2001ms is a gap.
      final borderline = [
        <String, dynamic>{'id': 1, 'timestamp': _t0, 'status': 0},
        <String, dynamic>{'id': 2, 'timestamp': _t0 + 2000, 'status': 0},
      ];
      final over = [
        <String, dynamic>{'id': 1, 'timestamp': _t0, 'status': 0},
        <String, dynamic>{'id': 2, 'timestamp': _t0 + 2001, 'status': 0},
      ];

      expect(
        TelemetryIntegrityService.validateSession(
          sessionId: 'session-a',
          events: borderline,
        ).gapCount,
        0,
      );
      expect(
        TelemetryIntegrityService.validateSession(
          sessionId: 'session-a',
          events: over,
        ).gapCount,
        1,
      );
    });

    test('a faster expected interval reclassifies the same data', () {
      // The same 1Hz data judged against a 5 FPS expectation is all gaps.
      final events = _events(5);

      final atOneHz = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );
      final atFiveFps = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
        expectedInterval: const Duration(milliseconds: 200),
      );

      expect(atOneHz.gapCount, 0);
      expect(atFiveFps.gapCount, 4);
    });
  });

  group('session with out-of-order timestamps', () {
    test('a backward jump is detected', () {
      // Sample 5 lands 3 seconds in the past — a clock rewind mid-session.
      final events = _events(10);
      events[5]['timestamp'] = (events[4]['timestamp'] as int) - 3000;

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.isValid, isFalse);
      expect(report.outOfOrderCount, 1);

      final backward = report.issues
          .where((i) => i.type == IntegrityIssueType.backwardJump)
          .toList();
      expect(backward, hasLength(1));
      expect(backward.single.index, 5);
      expect(backward.single.message, contains('backwards'));
    });

    test('the interval that recovers from a rewind is a gap, not a second '
        'backward jump', () {
      final events = _events(10);
      events[5]['timestamp'] = (events[4]['timestamp'] as int) - 3000;

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      // index 5 jumps back 3s; index 6 then leaps 4s forward to rejoin.
      expect(report.outOfOrderCount, 1);
      expect(report.gapCount, 1);
      expect(
        report.issues
            .firstWhere((i) => i.type == IntegrityIssueType.gap)
            .index,
        6,
      );
    });

    test('a fully reversed sequence faults every interval', () {
      final events = _events(5).reversed.toList();

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.outOfOrderCount, 4);
      expect(report.gapCount, 0, reason: 'sign makes the magnitude moot');
      expect(report.isValid, isFalse);
    });

    test('duplicate timestamps break strict order', () {
      final events = _events(5);
      events[3]['timestamp'] = events[2]['timestamp'];

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.outOfOrderCount, 1);
      expect(_types(report), contains(IntegrityIssueType.duplicateTimestamp));
    });
  });

  group('missing timestamps', () {
    test('null and absent timestamps are counted', () {
      final events = _events(5);
      events[1]['timestamp'] = null;
      events[3].remove('timestamp');

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.missingCount, 2);
      expect(report.isValid, isFalse);
      expect(report.sampleCount, 5, reason: 'bad rows still count as samples');
      expect(
        report.issues
            .where((i) => i.type == IntegrityIssueType.missingTimestamp)
            .map((i) => i.index),
        [1, 3],
      );
    });

    test('an unreadable timestamp type is counted as missing', () {
      final events = _events(3);
      events[1]['timestamp'] = 'not-a-timestamp';

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.missingCount, 1);
    });

    test('string and ISO-8601 timestamps from a JSON payload are accepted',
        () {
      final events = [
        <String, dynamic>{'timestamp': '$_t0', 'status': 0},
        <String, dynamic>{
          'timestamp':
              DateTime.fromMillisecondsSinceEpoch(_t0 + 1000).toIso8601String(),
          'status': 0,
        },
      ];

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.missingCount, 0);
      expect(report.isValid, isTrue, reason: report.toString());
    });

    test('dropping the rows around a hole reports both defects', () {
      final events = [
        ..._events(3),
        ..._events(3, startMs: _t0 + 9000),
      ];
      events[1]['timestamp'] = null;

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      );

      expect(report.missingCount, 1);
      expect(report.gapCount, 1);
    });
  });

  group('empty session', () {
    test('no events is invalid, not vacuously valid', () {
      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: const [],
      );

      expect(report.isValid, isFalse);
      expect(report.sampleCount, 0);
      expect(_types(report), [IntegrityIssueType.emptySession]);
    });
  });

  group('summary consistency', () {
    test('a duration that disagrees with the event span is reported', () {
      final events = _events(31); // spans 30s
      final summary = SessionSummary(
        sessionId: 'session-a',
        date: DateTime.fromMillisecondsSinceEpoch(events.last['timestamp'] as int),
        durationSeconds: 600, // claims 10 minutes
        goodPosturePercent: 100,
        longestStreakSeconds: 31,
      );

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
        summary: summary,
      );

      expect(_types(report), contains(IntegrityIssueType.durationMismatch));
      expect(report.isValid, isFalse);
    });

    test('truncated events under an intact summary are reported', () {
      // 61 samples were recorded; all but the endpoints were deleted.
      final events = [
        ..._events(1),
        ..._events(1, startMs: _t0 + 60000),
      ];
      final summary = SessionSummary(
        sessionId: 'session-a',
        date: DateTime.fromMillisecondsSinceEpoch(_t0 + 60000),
        durationSeconds: 60,
        goodPosturePercent: 100,
        longestStreakSeconds: 61,
      );

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
        summary: summary,
      );

      expect(_types(report), contains(IntegrityIssueType.sampleCountMismatch));
    });

    test('a summary stamped far from the last event is reported', () {
      final events = _events(31);
      final summary = SessionSummary(
        sessionId: 'session-a',
        date: DateTime.fromMillisecondsSinceEpoch(_t0 + 3600000),
        durationSeconds: 30,
        goodPosturePercent: 100,
        longestStreakSeconds: 31,
      );

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
        summary: summary,
      );

      expect(_types(report), contains(IntegrityIssueType.endTimeMismatch));
    });

    test('a worst-moment marker outside the session window is reported', () {
      final events = _events(31);
      final base = _summaryFor(events);
      final summary = SessionSummary(
        sessionId: base.sessionId,
        date: base.date,
        durationSeconds: base.durationSeconds,
        goodPosturePercent: base.goodPosturePercent,
        longestStreakSeconds: base.longestStreakSeconds,
        worstMomentTimestamp:
            DateTime.fromMillisecondsSinceEpoch(_t0 - 500000),
      );

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
        summary: summary,
      );

      expect(_types(report), contains(IntegrityIssueType.markerOutOfRange));
    });

    test('the endSession duration clamp is not inherited as truth', () {
      // endSession clamps duration to a minimum of 1s, so a zero-span
      // session reports 1s. That is within tolerance and must stay quiet.
      final events = _events(2, intervalMs: 0);
      final summary = SessionSummary(
        sessionId: 'session-a',
        date: DateTime.fromMillisecondsSinceEpoch(_t0),
        durationSeconds: 1,
        goodPosturePercent: 100,
        longestStreakSeconds: 2,
      );

      final report = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
        summary: summary,
      );

      expect(_types(report), isNot(contains(IntegrityIssueType.durationMismatch)));
      // The duplicate timestamp is still caught on its own merits.
      expect(_types(report), contains(IntegrityIssueType.duplicateTimestamp));
    });
  });

  group('report shape and arguments', () {
    test('toMap serialises the full verdict', () {
      final events = [..._events(2), ..._events(3, startMs: _t0 + 10000)];

      final map = TelemetryIntegrityService.validateSession(
        sessionId: 'session-a',
        events: events,
      ).toMap();

      expect(map['session_id'], 'session-a');
      expect(map['is_valid'], isFalse);
      expect(map['gap_count'], 1);
      expect(map['missing_count'], 0);
      expect(map['sample_count'], 5);
      expect(map['issues'], isA<List>().having((l) => l.length, 'length', 1));
    });

    test('hasOnlyGaps separates recoverable sessions from corrupt ones', () {
      final gapped = [..._events(3), ..._events(3, startMs: _t0 + 9000)];
      final reversed = _events(4).reversed.toList();

      expect(
        TelemetryIntegrityService.validateSession(
          sessionId: 'session-a',
          events: gapped,
        ).hasOnlyGaps,
        isTrue,
      );
      expect(
        TelemetryIntegrityService.validateSession(
          sessionId: 'session-a',
          events: reversed,
        ).hasOnlyGaps,
        isFalse,
      );
    });

    test('nonsensical thresholds are rejected', () {
      expect(
        () => TelemetryIntegrityService.validateSession(
          sessionId: 'session-a',
          events: _events(3),
          expectedInterval: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => TelemetryIntegrityService.validateSession(
          sessionId: 'session-a',
          events: _events(3),
          gapTolerance: 0.5,
        ),
        throwsArgumentError,
      );
    });
  });
}
