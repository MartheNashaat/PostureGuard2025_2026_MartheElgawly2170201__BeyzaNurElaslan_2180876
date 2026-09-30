// Section 1 stress test: measures CPU usage, battery consumption (%/hr),
// and thermal status across a sweep of detection frame rates.
//
// This is a standalone measurement tool, not part of the shipped app — it
// adds no screen or button to PostureGuard. Run it with `flutter drive`, not
// `flutter test`: `flutter test integration_test/...` uninstalls the app
// (and wipes its storage) the moment the run finishes; `flutter drive` does
// not, which is what leaves the app on the phone afterward.
//
//   flutter drive --driver=test_driver/integration_test.dart --target=integration_test/device_benchmark_test.dart -d <deviceId>
//
// Unplug the device first so the battery reading reflects real drain.
//
// The full CSV content is printed straight to this terminal at the end of
// the run, so you have it regardless — copy the printed "Raw CSV" /
// "Summary CSV" blocks into .csv files yourself. It's also saved on-device
// at the path printed alongside them, and since the app is no longer
// uninstalled afterward, that file is retrievable too via:
//
//   adb shell run-as com.postureguard.postureguard cat app_flutter/benchmarks/<filename>.csv
//
// Edit fpsList/phaseDuration below to match the run you want (quick sanity
// check vs. the real 30/60 min-per-rate stress test).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:postureguard/services/benchmark_runner.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('device benchmark: CPU / battery / thermal vs frame rate',
      (tester) async {
    // The camera plugin needs a widget tree with a valid context; this is
    // never shown as part of the app.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();

    final runner = BenchmarkRunner(
      // Section 1 continuous stress test: a single unbroken 30-min session
      // at unlimited (current production, unthrottled) frame rate, checking
      // stability/overheating under sustained use. Rerun with
      // Duration(minutes: 60) for the second required session. This is
      // separate from the 7-rate comparison sweep used earlier.
      targetFpsList: const [null],
      phaseDuration: const Duration(minutes: 30),
      onProgress: (msg) => debugPrint('[benchmark] $msg'),
    );

    final paths = await runner.run();
    debugPrint('[benchmark] done. raw=${paths.rawCsvPath} '
        'summary=${paths.summaryCsvPath}');
  }, timeout: const Timeout(Duration(hours: 4)));
}
