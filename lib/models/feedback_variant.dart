import 'package:flutter/material.dart';

/// Which feedback fires when posture stays bad for 5 s while the user is in
/// another app (PiP). Detection, scoring, logging, voice alerts, vibration and
/// the coloured border are identical in all three.
enum FeedbackVariant {
  /// Version A — the screen gradually dims until posture is corrected.
  dimming('A', 'Dimming', Icons.wb_sunny_outlined),

  /// Version B — a ghost of the calibrated posture is drawn over other apps.
  overlay('B', 'Baseline', Icons.accessibility_new),

  /// Version C — both at once.
  both('C', 'Both', Icons.layers_outlined);

  const FeedbackVariant(this.code, this.label, this.icon);

  /// `A`, `B` or `C`, as stored in the database and sent to the server.
  final String code;
  final String label;
  final IconData icon;

  bool get usesDimming => this == dimming || this == both;
  bool get usesOverlay => this == overlay || this == both;

  static FeedbackVariant? fromCode(String? code) {
    for (final v in values) {
      if (v.code == code) return v;
    }
    return null;
  }
}
