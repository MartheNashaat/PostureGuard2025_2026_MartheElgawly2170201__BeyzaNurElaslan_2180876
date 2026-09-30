// Driver entry point for `flutter drive`. Unlike `flutter test
// integration_test/...`, `flutter drive` does not uninstall the app when the
// run finishes — needed here so the benchmark CSVs written to the app's
// on-device storage survive after the run for manual inspection via `adb
// shell run-as`, and so the app itself stays installed on the phone.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
