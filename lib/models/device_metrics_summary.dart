/// Per-session resource cost, computed from the rows of the `device_metrics`
/// table. This is what gets reported per participant session (battery drain,
/// CPU, temperature), as opposed to the controlled Section 1 benchmarks.
///
/// Pure: takes rows in, returns numbers out, so it is unit-testable and the
/// upload payload can reuse it without touching the database.
class DeviceMetricsSummary {
  final String sessionId;
  final int sampleCount;
  final int durationSeconds;

  final double? startBatteryPercent;
  final double? endBatteryPercent;

  /// Battery percentage points lost while *not* charging. Intervals where
  /// either end was charging are skipped, so plugging in mid-session doesn't
  /// hide the drain from the rest of the session.
  final double batteryDropPercent;

  /// Seconds of the session spent discharging (the denominator for
  /// [batteryPercentPerHour]).
  final int dischargeSeconds;

  final bool chargedDuringSession;

  final double? avgCpuPercent;
  final double? maxCpuPercent;
  final double? avgBatteryTempC;
  final double? maxBatteryTempC;
  final String worstThermalStatus;

  /// Share of samples taken while the app was in picture-in-picture, i.e. the
  /// user was doing something else on the phone. 0-100.
  final double pipPercent;

  /// Share of samples taken with PiP closed (camera off, accelerometer-only
  /// mode). 0-100.
  final double backgroundPercent;

  /// Share of samples taken with battery saver on. 0-100.
  final double powerSavePercent;

  const DeviceMetricsSummary({
    required this.sessionId,
    required this.sampleCount,
    required this.durationSeconds,
    required this.startBatteryPercent,
    required this.endBatteryPercent,
    required this.batteryDropPercent,
    required this.dischargeSeconds,
    required this.chargedDuringSession,
    required this.avgCpuPercent,
    required this.maxCpuPercent,
    required this.avgBatteryTempC,
    required this.maxBatteryTempC,
    required this.worstThermalStatus,
    required this.pipPercent,
    required this.backgroundPercent,
    required this.powerSavePercent,
  });

  /// Battery drain in %/hr over the discharging part of the session.
  ///
  /// Android reports battery in whole percent, so short sessions give a coarse
  /// number: a 10-minute session that drops 1% reads as 6 %/hr, and one that
  /// drops 0% reads as 0. Null when there is under a minute of discharge time.
  double? get batteryPercentPerHour {
    if (dischargeSeconds < 60) return null;
    return batteryDropPercent / (dischargeSeconds / 3600);
  }

  static const _thermalOrder = [
    'unknown',
    'unsupported',
    'none',
    'light',
    'moderate',
    'severe',
    'critical',
    'emergency',
    'shutdown',
  ];

  static int _thermalSeverity(String s) {
    final i = _thermalOrder.indexOf(s);
    return i < 0 ? 0 : i;
  }

  /// [rows] are `device_metrics` rows for one session, in any order.
  factory DeviceMetricsSummary.fromRows(
    String sessionId,
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = [...rows]
      ..sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));

    double? numAt(Map<String, dynamic> r, String k) => (r[k] as num?)?.toDouble();
    bool flag(Map<String, dynamic> r, String k) => (r[k] as int? ?? 0) == 1;

    double drop = 0;
    int dischargeMs = 0;
    for (var i = 1; i < sorted.length; i++) {
      final prev = sorted[i - 1];
      final cur = sorted[i];
      if (flag(prev, 'is_charging') || flag(cur, 'is_charging')) continue;
      final a = numAt(prev, 'battery_percent');
      final b = numAt(cur, 'battery_percent');
      if (a == null || b == null) continue;
      dischargeMs += (cur['timestamp'] as int) - (prev['timestamp'] as int);
      if (a > b) drop += a - b;
    }

    final cpu = sorted.map((r) => numAt(r, 'cpu_percent')).whereType<double>().toList();
    final temp =
        sorted.map((r) => numAt(r, 'battery_temperature_c')).whereType<double>().toList();
    final battery =
        sorted.map((r) => numAt(r, 'battery_percent')).whereType<double>().toList();

    double? avg(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a + b) / v.length;
    double? max(List<double> v) => v.isEmpty ? null : v.reduce((a, b) => a > b ? a : b);
    double share(bool Function(Map<String, dynamic>) test) =>
        sorted.isEmpty ? 0 : sorted.where(test).length * 100 / sorted.length;

    return DeviceMetricsSummary(
      sessionId: sessionId,
      sampleCount: sorted.length,
      durationSeconds: sorted.length < 2
          ? 0
          : (((sorted.last['timestamp'] as int) - (sorted.first['timestamp'] as int)) / 1000)
              .round(),
      startBatteryPercent: battery.isEmpty ? null : battery.first,
      endBatteryPercent: battery.isEmpty ? null : battery.last,
      batteryDropPercent: drop,
      dischargeSeconds: (dischargeMs / 1000).round(),
      chargedDuringSession: sorted.any((r) => flag(r, 'is_charging')),
      avgCpuPercent: avg(cpu),
      maxCpuPercent: max(cpu),
      avgBatteryTempC: avg(temp),
      maxBatteryTempC: max(temp),
      worstThermalStatus: sorted
          .map((r) => r['thermal_status'] as String? ?? 'unknown')
          .fold('unknown', (w, c) => _thermalSeverity(c) > _thermalSeverity(w) ? c : w),
      pipPercent: share((r) => r['app_state'] == 'pip'),
      backgroundPercent: share((r) => r['app_state'] == 'background'),
      powerSavePercent: share((r) => flag(r, 'is_power_save')),
    );
  }

  /// Snake-case map matching the server schema, for the session upload.
  Map<String, dynamic> toJson() => {
        'session_id': sessionId,
        'sample_count': sampleCount,
        'duration_seconds': durationSeconds,
        'start_battery_percent': startBatteryPercent,
        'end_battery_percent': endBatteryPercent,
        'battery_drop_percent': batteryDropPercent,
        'discharge_seconds': dischargeSeconds,
        'battery_percent_per_hour': batteryPercentPerHour,
        'charged_during_session': chargedDuringSession,
        'avg_cpu_percent': avgCpuPercent,
        'max_cpu_percent': maxCpuPercent,
        'avg_battery_temp_c': avgBatteryTempC,
        'max_battery_temp_c': maxBatteryTempC,
        'worst_thermal_status': worstThermalStatus,
        'pip_percent': pipPercent,
        'background_percent': backgroundPercent,
        'power_save_percent': powerSavePercent,
      };
}
