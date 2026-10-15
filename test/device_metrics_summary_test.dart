import 'package:flutter_test/flutter_test.dart';
import 'package:postureguard/models/device_metrics_summary.dart';

const int _t0 = 1700000000000;

Map<String, dynamic> _row(
  int secondsIn, {
  double? battery,
  bool charging = false,
  double? cpu,
  double? temp,
  String thermal = 'none',
  String appState = 'foreground',
  bool powerSave = false,
}) =>
    {
      'session_id': 's',
      'timestamp': _t0 + secondsIn * 1000,
      'battery_percent': battery,
      'battery_temperature_c': temp,
      'is_charging': charging ? 1 : 0,
      'thermal_status': thermal,
      'cpu_percent': cpu,
      'cpu_cores': 8,
      'is_screen_on': 1,
      'is_power_save': powerSave ? 1 : 0,
      'app_state': appState,
    };

void main() {
  test('empty session gives zeros and nulls', () {
    final s = DeviceMetricsSummary.fromRows('s', []);
    expect(s.sampleCount, 0);
    expect(s.durationSeconds, 0);
    expect(s.batteryPercentPerHour, isNull);
    expect(s.avgCpuPercent, isNull);
  });

  test('drain rate over a steady one-hour discharge', () {
    final s = DeviceMetricsSummary.fromRows('s', [
      _row(0, battery: 90),
      _row(1800, battery: 85),
      _row(3600, battery: 80),
    ]);
    expect(s.durationSeconds, 3600);
    expect(s.batteryDropPercent, 10);
    expect(s.dischargeSeconds, 3600);
    expect(s.batteryPercentPerHour, closeTo(10, 1e-9));
    expect(s.chargedDuringSession, isFalse);
  });

  test('intervals touching a charging sample are excluded', () {
    final s = DeviceMetricsSummary.fromRows('s', [
      _row(0, battery: 50),
      _row(600, battery: 48),
      _row(1200, battery: 60, charging: true),
      _row(1800, battery: 62, charging: true),
      _row(2400, battery: 61),
    ]);
    // Only 0-600 counts: 2% over 10 minutes.
    expect(s.batteryDropPercent, 2);
    expect(s.dischargeSeconds, 600);
    expect(s.batteryPercentPerHour, closeTo(12, 1e-9));
    expect(s.chargedDuringSession, isTrue);
  });

  test('rows are sorted by timestamp before diffing', () {
    final s = DeviceMetricsSummary.fromRows('s', [
      _row(3600, battery: 80),
      _row(0, battery: 90),
    ]);
    expect(s.startBatteryPercent, 90);
    expect(s.endBatteryPercent, 80);
    expect(s.batteryDropPercent, 10);
  });

  test('cpu/temp aggregates skip nulls; worst thermal and shares', () {
    final s = DeviceMetricsSummary.fromRows('s', [
      _row(0, cpu: null, temp: 30, appState: 'foreground'),
      _row(15, cpu: 10, temp: 32, thermal: 'light', appState: 'pip'),
      _row(30, cpu: 20, temp: 34, thermal: 'moderate', appState: 'pip', powerSave: true),
      _row(45, cpu: 30, temp: 33, thermal: 'none', appState: 'pip'),
    ]);
    expect(s.avgCpuPercent, closeTo(20, 1e-9));
    expect(s.maxCpuPercent, 30);
    expect(s.avgBatteryTempC, closeTo(32.25, 1e-9));
    expect(s.maxBatteryTempC, 34);
    expect(s.worstThermalStatus, 'moderate');
    expect(s.pipPercent, 75);
    expect(s.backgroundPercent, 0);
    expect(s.powerSavePercent, 25);
  });

  test('background (PiP closed) share is counted separately from pip', () {
    final s = DeviceMetricsSummary.fromRows('s', [
      _row(0, appState: 'foreground'),
      _row(15, appState: 'pip'),
      _row(30, appState: 'background'),
      _row(45, appState: 'background'),
    ]);
    expect(s.pipPercent, 25);
    expect(s.backgroundPercent, 50);
  });

  test('under a minute of discharge gives no drain rate', () {
    final s = DeviceMetricsSummary.fromRows('s', [
      _row(0, battery: 50),
      _row(30, battery: 49),
    ]);
    expect(s.batteryPercentPerHour, isNull);
  });
}
