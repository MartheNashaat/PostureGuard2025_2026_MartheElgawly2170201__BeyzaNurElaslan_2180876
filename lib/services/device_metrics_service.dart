import 'package:flutter/services.dart';

/// One reading of device resource state, used by [BenchmarkScreen] to build
/// the CPU/battery/temperature-vs-frame-rate benchmarks for Section 1 of the
/// study plan.
class DeviceMetricsSample {
  final DateTime timestamp;
  final double? batteryPercent;
  final double? batteryTemperatureC;
  final bool isCharging;

  /// One of: none, light, moderate, severe, critical, emergency, shutdown,
  /// unsupported (API < 29), unknown.
  final String thermalStatus;

  /// This process's CPU usage since the previous sample, normalized to
  /// 0-100 across all cores. Null on the first sample of a run.
  final double? cpuPercent;
  final int? cpuCores;

  final bool isScreenOn;
  final bool isPowerSaveMode;

  const DeviceMetricsSample({
    required this.timestamp,
    required this.batteryPercent,
    required this.batteryTemperatureC,
    required this.isCharging,
    required this.thermalStatus,
    required this.cpuPercent,
    required this.cpuCores,
    this.isScreenOn = true,
    this.isPowerSaveMode = false,
  });
}

class DeviceMetricsService {
  static const MethodChannel _channel = MethodChannel('com.postureguard/overlay');

  /// Reads one metrics snapshot from the native side. CPU% is a delta since
  /// the previous call to this method (from anywhere in the app), so callers
  /// that need a clean baseline should discard the first sample of a run.
  static Future<DeviceMetricsSample> sample() async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceMetrics');
    final map = raw ?? const {};
    return DeviceMetricsSample(
      timestamp: DateTime.now(),
      batteryPercent: (map['batteryPercent'] as num?)?.toDouble(),
      batteryTemperatureC: (map['batteryTemperatureC'] as num?)?.toDouble(),
      isCharging: map['isCharging'] as bool? ?? false,
      thermalStatus: map['thermalStatus'] as String? ?? 'unknown',
      cpuPercent: (map['cpuPercent'] as num?)?.toDouble(),
      cpuCores: map['cpuCores'] as int?,
      isScreenOn: map['isScreenOn'] as bool? ?? true,
      isPowerSaveMode: map['isPowerSaveMode'] as bool? ?? false,
    );
  }
}
