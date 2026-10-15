import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:postureguard/models/integrity_report.dart';
import 'package:postureguard/models/session_summary.dart';
import 'package:postureguard/services/upload_payload.dart';

const int _t0 = 1790599044000;

Map<String, dynamic> _build({String? userId = 'Marthe01', String? variant = 'B'}) {
  final events = List.generate(
    3,
    (i) => <String, dynamic>{
      'id': i + 1,
      'session_id': 's1',
      'timestamp': _t0 + i * 1000,
      'status': i,
    },
  );
  final metrics = [
    {
      'session_id': 's1',
      'timestamp': _t0,
      'battery_percent': 80.0,
      'battery_temperature_c': 30.6,
      'is_charging': 0,
      'thermal_status': 'none',
      'cpu_percent': null,
      'cpu_cores': 10,
      'is_screen_on': 1,
      'is_power_save': 0,
      'app_state': 'pip',
    },
  ];
  return buildSessionPayload(
    summary: SessionSummary(
      sessionId: 's1',
      date: DateTime.fromMillisecondsSinceEpoch(_t0 + 2000),
      durationSeconds: 2,
      goodPosturePercent: 33.3,
      longestStreakSeconds: 1,
      variant: variant,
      userId: userId,
    ),
    events: events,
    metricsRows: metrics,
    integrity: IntegrityReport.clean(sessionId: 's1', sampleCount: 3),
    device: const DeviceInfo(
      manufacturer: 'samsung',
      model: 'SM-A546B',
      androidVersion: '14',
      appVersion: '1.0.0+1',
      cpuCores: 10,
    ),
  );
}

void main() {
  test('top level matches API_SCHEMA.md', () {
    final p = _build();
    expect(p.keys.toSet(), {
      'user_id', 'session_id', 'variant', 'app_version', 'session', 'device',
      'detection', 'integrity', 'events', 'device_metrics',
      'device_metrics_summary',
    });
    expect(p['user_id'], 'Marthe01');
    expect(p['session_id'], 's1');
    expect(p['variant'], 'B');
    expect(p['app_version'], '1.0.0+1');
  });

  test('user id is sent exactly as stored', () {
    expect(_build(userId: 'abC123')['user_id'], 'abC123');
  });

  test('session block uses first/last event as start/end', () {
    final s = _build()['session'] as Map;
    expect(s['started_at'], _t0);
    expect(s['ended_at'], _t0 + 2000);
    expect(s['duration_seconds'], 2);
  });

  test('events are {t, status} per second', () {
    final e = _build()['events'] as List;
    expect(e, hasLength(3));
    expect(e.first, {'t': _t0, 'status': 0});
  });

  test('device metrics flags become booleans', () {
    final m = (_build()['device_metrics'] as List).single as Map;
    expect(m['t'], _t0);
    expect(m['is_charging'], false);
    expect(m['is_screen_on'], true);
    expect(m['app_state'], 'pip');
    expect(m['cpu_percent'], isNull);
  });

  test('summary has no duplicate session_id and includes background share', () {
    final s = _build()['device_metrics_summary'] as Map;
    expect(s.containsKey('session_id'), isFalse);
    expect(s['pip_percent'], 100);
    expect(s.containsKey('background_percent'), isTrue);
  });

  test('whole payload is JSON-encodable', () {
    expect(() => jsonEncode(_build()), returnsNormally);
  });
}
