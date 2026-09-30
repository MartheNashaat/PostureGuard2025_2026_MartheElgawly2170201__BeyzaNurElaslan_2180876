import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Where the session is visible, as reported by MainActivity:
/// `foreground` (full screen), `pip`, or `background` (PiP closed — camera
/// stopped, accelerometer-only mode).
///
/// Dart can't tell PiP from a closed PiP window on its own: the widget tree
/// simply stops building, so the last known PiP size sticks. The activity's
/// own lifecycle is the reliable source.
class WindowStateService {
  static const MethodChannel _channel = MethodChannel('com.postureguard/window');

  static final ValueNotifier<String> state = ValueNotifier('foreground');

  static bool get isBackground => state.value == 'background';

  static Future<void> init() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'windowState' && call.arguments is String) {
        state.value = call.arguments as String;
      }
    });
    try {
      final current = await _channel.invokeMethod<String>('getWindowState');
      if (current != null) state.value = current;
    } catch (_) {
      // Not available (tests, non-Android): stay on the default.
    }
  }
}
