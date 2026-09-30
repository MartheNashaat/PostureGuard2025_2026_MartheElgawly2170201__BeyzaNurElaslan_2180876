import '../config.dart';
import '../models/device_metrics_summary.dart';
import '../models/integrity_report.dart';
import '../models/session_summary.dart';

/// Phone details sent with every session (from MainActivity.getDeviceInfo).
class DeviceInfo {
  final String? manufacturer;
  final String? model;
  final String? androidVersion;
  final String? appVersion;
  final int? cpuCores;

  const DeviceInfo({
    this.manufacturer,
    this.model,
    this.androidVersion,
    this.appVersion,
    this.cpuCores,
  });

  factory DeviceInfo.fromMap(Map<dynamic, dynamic> m) => DeviceInfo(
        manufacturer: m['manufacturer'] as String?,
        model: m['model'] as String?,
        androidVersion: m['androidVersion'] as String?,
        appVersion: m['appVersion'] as String?,
        cpuCores: m['cpuCores'] as int?,
      );
}

/// Builds the session upload body defined in `study/API_SCHEMA.md`.
///
/// Pure — the caller supplies rows already read from SQLite. Only
/// [TelemetryIntegrityGate] should call this, and only for sessions that
/// passed validation, so the check can't be skipped.
Map<String, dynamic> buildSessionPayload({
  required SessionSummary summary,
  required List<Map<String, dynamic>> events,
  required List<Map<String, dynamic>> metricsRows,
  required IntegrityReport integrity,
  required DeviceInfo device,
}) {
  bool flag(Object? v) => v == 1 || v == true;
  final metricsSummary = DeviceMetricsSummary.fromRows(summary.sessionId, metricsRows);

  return {
    'user_id': summary.userId,
    'session_id': summary.sessionId,
    'variant': summary.variant,
    'app_version': device.appVersion,
    'session': {
      'started_at': events.isEmpty ? null : events.first['timestamp'],
      'ended_at': events.isEmpty ? null : events.last['timestamp'],
      'duration_seconds': summary.durationSeconds,
      'good_posture_percent': summary.goodPosturePercent,
      'longest_streak_seconds': summary.longestStreakSeconds,
      'worst_moment_timestamp': summary.worstMomentTimestamp?.millisecondsSinceEpoch,
    },
    'device': {
      'manufacturer': device.manufacturer,
      'model': device.model,
      'android_version': device.androidVersion,
      'cpu_cores': device.cpuCores,
    },
    'detection': {
      'foreground_fps': AppConfig.foregroundDetectionFps,
      'pip_fps': AppConfig.pipDetectionFps,
    },
    'integrity': {
      'is_valid': integrity.isValid,
      'gap_count': integrity.gapCount,
      'missing_count': integrity.missingCount,
    },
    'events': [
      for (final e in events) {'t': e['timestamp'], 'status': e['status']},
    ],
    'device_metrics': [
      for (final r in metricsRows)
        {
          't': r['timestamp'],
          'battery_percent': r['battery_percent'],
          'battery_temperature_c': r['battery_temperature_c'],
          'is_charging': flag(r['is_charging']),
          'thermal_status': r['thermal_status'],
          'cpu_percent': r['cpu_percent'],
          'is_screen_on': flag(r['is_screen_on']),
          'is_power_save': flag(r['is_power_save']),
          'app_state': r['app_state'],
        },
    ],
    'device_metrics_summary': metricsSummary.toJson()..remove('session_id'),
  };
}
