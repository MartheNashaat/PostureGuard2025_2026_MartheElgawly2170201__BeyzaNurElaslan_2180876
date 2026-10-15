import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../models/device_metrics_summary.dart';
import 'database_service.dart';
import 'device_metrics_service.dart';

/// Samples battery / CPU / temperature for the whole of a real posture
/// session, including while the app sits in picture-in-picture and the user
/// is using other apps, and stores each sample in the `device_metrics` table.
///
/// This is the in-the-wild counterpart to [BenchmarkRunner]: that one
/// measures fixed frame rates under controlled conditions, this one measures
/// what a participant's phone actually pays during normal use.
class SessionMetricsRecorder {
  SessionMetricsRecorder({
    required this.sessionId,
    required this.appState,
    this.interval = const Duration(seconds: 15),
  });

  final String sessionId;

  /// Returns `foreground`, `pip` or `background` at the moment of sampling.
  final String Function() appState;

  final Duration interval;

  Timer? _timer;
  bool _primed = false;

  Future<void> start() async {
    // CPU% is a delta since the previous native call, which could be minutes
    // old (e.g. an earlier benchmark). Prime the baseline, then record the
    // first real sample with its CPU dropped.
    try {
      await DeviceMetricsService.sample();
    } catch (e) {
      debugPrint('SessionMetricsRecorder: metrics unavailable: $e');
      return;
    }
    await _record(dropCpu: true);
    _primed = true;
    _timer = Timer.periodic(interval, (_) => _record());
  }

  /// Takes one final sample so the battery reading covers the full session.
  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_primed) await _record();
  }

  /// Cancel without a final sample (widget disposed without ending).
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _record({bool dropCpu = false}) async {
    try {
      var s = await DeviceMetricsService.sample();
      if (dropCpu) {
        s = DeviceMetricsSample(
          timestamp: s.timestamp,
          batteryPercent: s.batteryPercent,
          batteryTemperatureC: s.batteryTemperatureC,
          isCharging: s.isCharging,
          thermalStatus: s.thermalStatus,
          cpuPercent: null,
          cpuCores: s.cpuCores,
          isScreenOn: s.isScreenOn,
          isPowerSaveMode: s.isPowerSaveMode,
        );
      }
      await DatabaseService.logDeviceMetrics(
        sessionId: sessionId,
        sample: s,
        appState: appState(),
      );
    } catch (e) {
      // A missed sample only widens one interval; never break the session.
      debugPrint('SessionMetricsRecorder: sample failed: $e');
    }
  }

  // ─── CSV export (for pulling test results off the phone) ───

  static const _rawHeader = 'session_id,timestamp,iso_time,battery_percent,'
      'battery_temperature_c,is_charging,thermal_status,cpu_percent,cpu_cores,'
      'is_screen_on,is_power_save,app_state';

  static const _summaryHeader = 'session_id,date,duration_min,sample_count,'
      'start_battery_percent,end_battery_percent,battery_drop_percent,'
      'discharge_min,battery_pct_per_hr,charged_during_session,avg_cpu_percent,'
      'max_cpu_percent,avg_battery_temp_c,max_battery_temp_c,'
      'worst_thermal_status,pip_percent,power_save_percent,background_percent';

  /// Writes `session_<id>_metrics.csv` and appends one row to
  /// `sessions_summary.csv`, both under
  /// `Android/data/com.postureguard.postureguard/files/session_metrics/`
  /// (reachable over USB or `adb pull`). Returns the summary.
  static Future<DeviceMetricsSummary> exportSession(String sessionId) async {
    final rows = await DatabaseService.getSessionDeviceMetrics(sessionId);
    final summary = DeviceMetricsSummary.fromRows(sessionId, rows);

    try {
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final dir = Directory('${base.path}/session_metrics');
      if (!await dir.exists()) await dir.create(recursive: true);

      String v(Object? x) => x == null ? '' : '$x';
      String f(double? x, [int d = 1]) => x == null ? '' : x.toStringAsFixed(d);

      final raw = StringBuffer('$_rawHeader\n');
      for (final r in rows) {
        final ts = r['timestamp'] as int;
        raw.writeln([
          sessionId,
          ts,
          DateTime.fromMillisecondsSinceEpoch(ts).toIso8601String(),
          v(r['battery_percent']),
          v(r['battery_temperature_c']),
          v(r['is_charging']),
          v(r['thermal_status']),
          f((r['cpu_percent'] as num?)?.toDouble(), 2),
          v(r['cpu_cores']),
          v(r['is_screen_on']),
          v(r['is_power_save']),
          v(r['app_state']),
        ].join(','));
      }
      await File('${dir.path}/session_${sessionId}_metrics.csv')
          .writeAsString(raw.toString());

      final summaryFile = File('${dir.path}/sessions_summary.csv');
      final line = [
        sessionId,
        DateTime.now().toIso8601String(),
        (summary.durationSeconds / 60).toStringAsFixed(2),
        summary.sampleCount,
        f(summary.startBatteryPercent),
        f(summary.endBatteryPercent),
        f(summary.batteryDropPercent),
        (summary.dischargeSeconds / 60).toStringAsFixed(2),
        f(summary.batteryPercentPerHour, 2),
        summary.chargedDuringSession,
        f(summary.avgCpuPercent),
        f(summary.maxCpuPercent),
        f(summary.avgBatteryTempC),
        f(summary.maxBatteryTempC),
        summary.worstThermalStatus,
        summary.pipPercent.toStringAsFixed(0),
        summary.powerSavePercent.toStringAsFixed(0),
        summary.backgroundPercent.toStringAsFixed(0),
      ].join(',');
      // A file from an older build has fewer columns; start a fresh one rather
      // than appending rows that don't match its header.
      if (await summaryFile.exists() &&
          (await summaryFile.readAsLines()).first != _summaryHeader) {
        await summaryFile.rename('${dir.path}/sessions_summary_old_${DateTime.now().millisecondsSinceEpoch}.csv');
      }
      final needsHeader = !await summaryFile.exists();
      await summaryFile.writeAsString(
        '${needsHeader ? '$_summaryHeader\n' : ''}$line\n',
        mode: FileMode.append,
      );

      debugPrint('Session metrics saved to ${dir.path}');
      debugPrint('$_summaryHeader\n$line');
    } catch (e) {
      debugPrint('SessionMetricsRecorder: CSV export failed: $e');
    }
    return summary;
  }
}
