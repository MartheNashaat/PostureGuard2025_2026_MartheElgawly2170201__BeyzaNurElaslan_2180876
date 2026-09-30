import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'camera_service.dart';
import 'detection_service.dart';
import 'device_metrics_service.dart';
import 'frame_rate_limiter.dart';

/// Result of one frame-rate phase of a benchmark sweep.
class BenchmarkPhaseResult {
  final double? targetFps;
  final Duration duration;
  final double? startBatteryPercent;
  final double? endBatteryPercent;
  final bool chargingDuringRun;
  final double? avgCpuPercent;
  final double? maxCpuPercent;
  final double? avgBatteryTempC;
  final double? maxBatteryTempC;
  final String worstThermalStatus;
  final double avgActualFps;

  BenchmarkPhaseResult({
    required this.targetFps,
    required this.duration,
    required this.startBatteryPercent,
    required this.endBatteryPercent,
    required this.chargingDuringRun,
    required this.avgCpuPercent,
    required this.maxCpuPercent,
    required this.avgBatteryTempC,
    required this.maxBatteryTempC,
    required this.worstThermalStatus,
    required this.avgActualFps,
  });

  /// %/hr, positive = draining. Not meaningful if [chargingDuringRun].
  double? get batteryPercentPerHour {
    if (startBatteryPercent == null || endBatteryPercent == null) return null;
    final hours = duration.inMilliseconds / (1000 * 60 * 60);
    if (hours <= 0) return null;
    return (startBatteryPercent! - endBatteryPercent!) / hours;
  }
}

class BenchmarkPaths {
  final String rawCsvPath;
  final String summaryCsvPath;
  final String rawCsvContent;
  final String summaryCsvContent;
  BenchmarkPaths(
    this.rawCsvPath,
    this.summaryCsvPath,
    this.rawCsvContent,
    this.summaryCsvContent,
  );
}

const _thermalRank = [
  'none',
  'light',
  'moderate',
  'severe',
  'critical',
  'emergency',
  'shutdown',
];

int _thermalSeverity(String status) {
  final i = _thermalRank.indexOf(status);
  return i < 0 ? -1 : i;
}

/// Drives the real camera + ML Kit detection pipeline through a sequence of
/// target frame rates, logging CPU%, battery drain, and thermal status for
/// each, and writes the results to CSV. No UI of its own — meant to be
/// invoked from `integration_test/device_benchmark_test.dart`, never from
/// the shipped app.
///
/// This is Section 1 of the study plan: "Measure CPU usage, battery
/// consumption (%/hr), and device temperature profiles across different
/// frame rates."
class BenchmarkRunner {
  BenchmarkRunner({
    required this.targetFpsList,
    required this.phaseDuration,
    this.sampleInterval = const Duration(seconds: 5),
    this.onProgress,
  });

  /// Frame rates to test, in order. Use null for "unlimited" (current
  /// drop-if-busy behavior with no throttle).
  final List<double?> targetFpsList;
  final Duration phaseDuration;
  final Duration sampleInterval;
  final void Function(String message)? onProgress;

  final CameraService _cameraService = CameraService();
  final DetectionService _detectionService = DetectionService();

  void _log(String message) => onProgress?.call(message);

  /// Runs the full sweep and writes both CSVs. Returns their paths.
  Future<BenchmarkPaths> run() async {
    final rawRows = <String>[
      'target_fps,elapsed_s,actual_fps,battery_percent,battery_temp_c,thermal_status,cpu_percent,is_charging',
    ];
    final results = <BenchmarkPhaseResult>[];

    await WakelockPlus.enable();
    await _cameraService.initialize();

    try {
      for (var i = 0; i < targetFpsList.length; i++) {
        final targetFps = targetFpsList[i];
        _log('Phase ${i + 1}/${targetFpsList.length}: target '
            '${targetFps == null ? "unlimited" : "$targetFps fps"} for '
            '${phaseDuration.inMinutes} min');
        final result = await _runPhase(targetFps: targetFps, rawRows: rawRows);
        if (result != null) {
          results.add(result);
          _log('  -> avg CPU ${result.avgCpuPercent?.toStringAsFixed(1) ?? "?"}%, '
              'battery ${result.batteryPercentPerHour?.toStringAsFixed(2) ?? "?"} %/hr, '
              'worst thermal ${result.worstThermalStatus}');
        }
      }
    } finally {
      await _cameraService.stopImageStream();
      await _cameraService.dispose();
      await _detectionService.dispose();
      await WakelockPlus.disable();
    }

    return _saveResults(rawRows, results);
  }

  Future<BenchmarkPhaseResult?> _runPhase({
    required double? targetFps,
    required List<String> rawRows,
  }) async {
    final limiter = FrameRateLimiter(targetFps);
    final desc = _cameraService.cameraDescription;
    if (desc == null) return null;

    // Discard one sample so this phase's CPU% baseline doesn't include
    // whatever ran immediately before it.
    await DeviceMetricsService.sample();

    final stopwatch = Stopwatch()..start();
    final samples = <DeviceMetricsSample>[];
    double? startBattery;
    bool sawCharging = false;

    _cameraService.startImageStream((CameraImage image) {
      if (!limiter.shouldProcess()) return;
      _detectionService.processFrame(image, desc);
    });

    while (stopwatch.elapsed < phaseDuration) {
      await Future.delayed(sampleInterval);
      final s = await DeviceMetricsService.sample();
      samples.add(s);
      startBattery ??= s.batteryPercent;
      if (s.isCharging) sawCharging = true;
      final actualFps = limiter.passedCount /
          (stopwatch.elapsed.inMilliseconds / 1000).clamp(0.001, double.infinity);
      rawRows.add(
        '${targetFps ?? "unlimited"},'
        '${stopwatch.elapsed.inSeconds},'
        '${actualFps.toStringAsFixed(2)},'
        '${s.batteryPercent?.toStringAsFixed(1) ?? ""},'
        '${s.batteryTemperatureC?.toStringAsFixed(1) ?? ""},'
        '${s.thermalStatus},'
        '${s.cpuPercent?.toStringAsFixed(1) ?? ""},'
        '${s.isCharging}',
      );
    }

    await _cameraService.stopImageStream();

    final endSample = await DeviceMetricsService.sample();
    samples.add(endSample);
    if (endSample.isCharging) sawCharging = true;

    final cpuValues = samples.map((s) => s.cpuPercent).whereType<double>().toList();
    final tempValues = samples.map((s) => s.batteryTemperatureC).whereType<double>().toList();
    final worstThermal = samples.map((s) => s.thermalStatus).fold<String>(
      'none',
      (worst, cur) => _thermalSeverity(cur) > _thermalSeverity(worst) ? cur : worst,
    );

    return BenchmarkPhaseResult(
      targetFps: targetFps,
      duration: stopwatch.elapsed,
      startBatteryPercent: startBattery,
      endBatteryPercent: endSample.batteryPercent,
      chargingDuringRun: sawCharging,
      avgCpuPercent: cpuValues.isEmpty ? null : cpuValues.reduce((a, b) => a + b) / cpuValues.length,
      maxCpuPercent: cpuValues.isEmpty ? null : cpuValues.reduce((a, b) => a > b ? a : b),
      avgBatteryTempC: tempValues.isEmpty ? null : tempValues.reduce((a, b) => a + b) / tempValues.length,
      maxBatteryTempC: tempValues.isEmpty ? null : tempValues.reduce((a, b) => a > b ? a : b),
      worstThermalStatus: worstThermal,
      avgActualFps:
          limiter.passedCount / (stopwatch.elapsed.inMilliseconds / 1000).clamp(0.001, double.infinity),
    );
  }

  Future<BenchmarkPaths> _saveResults(
    List<String> rawRows,
    List<BenchmarkPhaseResult> results,
  ) async {
    final dir = await getApplicationDocumentsDirectory();
    final benchDir = Directory('${dir.path}/benchmarks');
    if (!await benchDir.exists()) await benchDir.create(recursive: true);

    final stamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final rawFile = File('${benchDir.path}/benchmark_$stamp.csv');
    await rawFile.writeAsString(rawRows.join('\n'));

    final summaryRows = <String>[
      'target_fps,duration_min,start_battery_percent,end_battery_percent,'
          'battery_pct_per_hr,charging_during_run,avg_cpu_percent,max_cpu_percent,'
          'avg_battery_temp_c,max_battery_temp_c,worst_thermal_status,avg_actual_fps',
    ];
    for (final r in results) {
      summaryRows.add(
        '${r.targetFps ?? "unlimited"},'
        '${(r.duration.inSeconds / 60).toStringAsFixed(2)},'
        '${r.startBatteryPercent?.toStringAsFixed(1) ?? ""},'
        '${r.endBatteryPercent?.toStringAsFixed(1) ?? ""},'
        '${r.batteryPercentPerHour?.toStringAsFixed(2) ?? ""},'
        '${r.chargingDuringRun},'
        '${r.avgCpuPercent?.toStringAsFixed(1) ?? ""},'
        '${r.maxCpuPercent?.toStringAsFixed(1) ?? ""},'
        '${r.avgBatteryTempC?.toStringAsFixed(1) ?? ""},'
        '${r.maxBatteryTempC?.toStringAsFixed(1) ?? ""},'
        '${r.worstThermalStatus},'
        '${r.avgActualFps.toStringAsFixed(2)}',
      );
    }
    final summaryFile = File('${benchDir.path}/benchmark_${stamp}_summary.csv');
    await summaryFile.writeAsString(summaryRows.join('\n'));

    final rawContent = rawRows.join('\n');
    final summaryContent = summaryRows.join('\n');

    _log('Raw CSV (also on-device at ${rawFile.path}):');
    _log(rawContent);
    _log('Summary CSV (also on-device at ${summaryFile.path}):');
    _log(summaryContent);

    return BenchmarkPaths(rawFile.path, summaryFile.path, rawContent, summaryContent);
  }
}
