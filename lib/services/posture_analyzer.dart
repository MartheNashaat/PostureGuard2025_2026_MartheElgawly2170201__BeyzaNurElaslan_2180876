// lib/services/posture_analyzer.dart
import '../models/calibration_data.dart';
import '../models/posture_status.dart';
import '../services/detection_service.dart';

class PostureAnalysisResult {
  final PostureStatus status;
  final bool shoulderAsymmetry;
  final bool headTilt;
  final bool shoulderRounding;
  final bool headRise;          // camera: nose rose above baseline (head moved up)
  final bool headDrop;          // camera: nose dropped below baseline (head moved down)
  final bool phoneTooLow;       // accel/camera: phone physically too low
  final bool phoneTooHigh;      // accel/camera: phone physically too high
  final bool personOffScreen;   // landmarks detected but person is outside the visible frame
  final double shoulderSymmetryPercent;
  final double headTiltPercent;
  final double shoulderRoundingPercent;
  final double headRisePercent;
  final double headDropPercent;
  final double phoneTooLowPercent;
  final double phoneTooHighPercent;

  const PostureAnalysisResult({
    required this.status,
    required this.shoulderAsymmetry,
    required this.headTilt,
    required this.shoulderRounding,
    required this.headRise,
    required this.headDrop,
    required this.phoneTooLow,
    required this.phoneTooHigh,
    this.personOffScreen = false,
    this.shoulderSymmetryPercent = 100,
    this.headTiltPercent = 100,
    this.shoulderRoundingPercent = 100,
    this.headRisePercent = 100,
    this.headDropPercent = 100,
    this.phoneTooLowPercent = 100,
    this.phoneTooHighPercent = 100,
  });

  int get violationCount =>
      (shoulderAsymmetry ? 1 : 0) +
      (headTilt ? 1 : 0) +
      (shoulderRounding ? 1 : 0) +
      (headRise ? 1 : 0) +
      (headDrop ? 1 : 0) +
      (phoneTooLow ? 1 : 0) +
      (phoneTooHigh ? 1 : 0);

  double get overallScore {
    final scores = [
      shoulderSymmetryPercent,
      headTiltPercent,
      shoulderRoundingPercent,
      headRisePercent,
      headDropPercent,
      phoneTooLowPercent,
      phoneTooHighPercent,
    ];
    return (scores.reduce((a, b) => a + b) / scores.length).clamp(0.0, 100.0);
  }

  List<String> get violationMessages {
    // Accel-based phone position has highest priority.
    if (phoneTooHigh) return ['Phone too high — lower it'];
    if (phoneTooLow)  return ['Phone too low — raise it'];
    // Camera-based head position.
    if (headDrop) return ['Head dropped'];
    if (headRise) return ['Head raised'];
    // Body posture — each fires only for its own cause.
    final messages = <String>[];
    if (shoulderAsymmetry) messages.add('Shoulders uneven');
    if (headTilt)          messages.add('Head tilting');
    if (shoulderRounding)  messages.add('Shoulders rounding');
    return messages;
  }

  static const good = PostureAnalysisResult(
    status: PostureStatus.good,
    shoulderAsymmetry: false,
    headTilt: false,
    shoulderRounding: false,
    headRise: false,
    headDrop: false,
    phoneTooLow: false,
    phoneTooHigh: false,
  );
}

class PostureAnalyzer {
  final CalibrationData calibration;

  // EMA smoothing on camera NTS.
  // 0.25 (up from 0.15): faster response so the NTS soft zone suppresses
  // shoulder checks sooner when the phone starts moving up/down.
  static const double _ntsAlpha = 0.25;
  double _smoothNTS = double.nan;

  // Camera NTS hysteresis — head position relative to shoulders.
  bool _headRaiseActive = false;
  bool _headDropActive  = false;

  // Accel hysteresis — phone position.
  bool _accelTooLowActive  = false;
  bool _accelTooHighActive = false;

  // Camera hysteresis for phone-too-low: requires all 4 landmarks to drop
  // back below half the entry threshold before clearing, so a single noisy
  // frame cannot briefly drop the state and let phoneTooHigh flash through.
  bool _cameraTooLowActive = false;

  // Body-check hysteresis — prevents per-frame flickering on all three checks.
  bool _headTiltActive          = false;
  bool _shoulderAsymmetryActive = false;
  bool _shoulderRoundingActive  = false;

  PostureAnalyzer(this.calibration);

  PostureAnalysisResult analyze(
    NormalizedLandmarks landmarks, {
    double? accelX,
    double? accelY,
    double? accelZ,
  }) {
    // ── Shoulder width (scale reference) ─────────────────────────────────────
    final currentShoulderWidth = (landmarks.leftShoulderX - landmarks.rightShoulderX).abs();
    final safeWidth         = currentShoulderWidth.clamp(0.01, 1.0);
    final safeBaselineWidth = calibration.shoulderWidth.clamp(0.01, 1.0);

    // ── Camera NTS: head/nose position relative to shoulders ─────────────────
    // NTS = (shoulderMidY – noseY) / shoulderWidth. Scale-invariant.
    // Increases when nose appears higher (head up / phone lower).
    // Decreases when nose appears lower (head down / phone higher).
    final currentShoulderMidY  = (landmarks.leftShoulderY  + landmarks.rightShoulderY)  / 2;
    final baselineShoulderMidY = (calibration.leftShoulderY + calibration.rightShoulderY) / 2;
    final rawNTS      = (currentShoulderMidY  - landmarks.noseY)  / safeWidth;
    final baselineNTS = (baselineShoulderMidY - calibration.noseY) / safeBaselineWidth;

    if (_smoothNTS.isNaN) {
      _smoothNTS = rawNTS;
    } else {
      _smoothNTS = _ntsAlpha * rawNTS + (1 - _ntsAlpha) * _smoothNTS;
    }

    final ratioThreshold = calibration.headDropThreshold / safeBaselineWidth;
    // 0.35× (down from 0.50×): soft zone fires earlier so shoulder checks are
    // suppressed as soon as the phone starts moving, before the hard violation fires.
    final ratioSoft = ratioThreshold * 0.35;

    // headRise: nose above baseline (NTS increased)
    final ntsRise = (_smoothNTS - baselineNTS).clamp(0.0, double.infinity);
    final headRisePercent = (1.0 - ntsRise / ratioThreshold).clamp(0.0, 1.0) * 100;

    // headDrop: nose below baseline (NTS decreased)
    final ntsDrop = (baselineNTS - _smoothNTS).clamp(0.0, double.infinity);
    final headDropPercent = (1.0 - ntsDrop / ratioThreshold).clamp(0.0, 1.0) * 100;

    // Camera hysteresis: 65% exit (smooth EMA signal — tight band is fine).
    const cameraHysteresisExit = 0.65;
    if (ntsRise > ratioThreshold) {
      _headRaiseActive = true;
      _headDropActive  = false;
    } else if (_headRaiseActive && ntsRise < ratioThreshold * cameraHysteresisExit) {
      _headRaiseActive = false;
    }
    if (ntsDrop > ratioThreshold) {
      _headDropActive  = true;
      _headRaiseActive = false;
    } else if (_headDropActive && ntsDrop < ratioThreshold * cameraHysteresisExit) {
      _headDropActive = false;
    }

    final bool headRise = _headRaiseActive;
    final bool headDrop = _headDropActive;

    // ── Accelerometer: phone position via Y-axis vs calibration baseline ─────
    // Asymmetric thresholds: accelY rises less going up than it drops going down
    // from a typical calibration angle, so "too high" uses a smaller entry value.
    const double yHighEntry = 0.5;   // m/s² — phone moved up
    const double yHighExit  = 0.0;   // clear as soon as Y drops back to baseline
    const double yLowEntry  = 1.5;   // m/s² — phone moved down
    const double yLowExit   = 1.05;
    double phoneTooLowPercent  = 100.0;
    double phoneTooHighPercent = 100.0;

    if (accelY != null) {
      final yDiff = accelY - calibration.accelY;
      phoneTooHighPercent = (1.0 - (yDiff  / yHighEntry).clamp(0.0, 1.0)) * 100;
      phoneTooLowPercent  = (1.0 - (-yDiff / yLowEntry).clamp(0.0, 1.0)) * 100;

      if (yDiff > yHighEntry) {
        _accelTooHighActive = true;
        _accelTooLowActive  = false;
      } else if (_accelTooHighActive && yDiff < yHighExit) {
        _accelTooHighActive = false;
      }
      if (yDiff < -yLowEntry) {
        _accelTooLowActive  = true;
        _accelTooHighActive = false;
      } else if (_accelTooLowActive && yDiff > -yLowExit) {
        _accelTooLowActive = false;
      }
    }

    // Camera-based phone position: detect uniform landmark shifts in the frame.
    // When phone is LOW  → camera angles up   → all landmarks appear ABOVE baseline (smaller Y).
    // When phone is HIGH → camera angles down → all landmarks appear BELOW baseline (larger Y).
    // Guards use the NTS soft zone to distinguish phone movement from head movement:
    //   ntsRise rising  → head is going up relative to shoulders → not phone-too-low
    //   ntsDrop rising  → head is going down relative to shoulders → not phone-too-high
    const double camThreshold = 0.08; // 8% of frame — filters small tilt-induced shifts
    final double camShoulderMidY = (landmarks.leftShoulderY + landmarks.rightShoulderY) / 2;
    final double calShoulderMidY = (calibration.leftShoulderY + calibration.rightShoulderY) / 2;

    final bool cameraPhoneTooLowRaw =
        ntsRise < ratioSoft &&
        (calibration.noseY     - landmarks.noseY)     > camThreshold &&
        (calibration.leftEarY  - landmarks.leftEarY)  > camThreshold &&
        (calibration.rightEarY - landmarks.rightEarY) > camThreshold &&
        (calShoulderMidY       - camShoulderMidY)      > camThreshold;

    // Exit uses half the entry threshold — requires a clear return toward baseline
    // before clearing, so a single noisy frame cannot briefly drop the state.
    const double camLowExit = camThreshold * 0.5;
    if (cameraPhoneTooLowRaw) {
      _cameraTooLowActive = true;
    } else if (_cameraTooLowActive &&
        (ntsRise >= ratioSoft ||
         (calibration.noseY     - landmarks.noseY)     < camLowExit ||
         (calibration.leftEarY  - landmarks.leftEarY)  < camLowExit ||
         (calibration.rightEarY - landmarks.rightEarY) < camLowExit ||
         (calShoulderMidY       - camShoulderMidY)      < camLowExit)) {
      _cameraTooLowActive = false;
    }

    final bool cameraPhoneTooHigh =
        ntsDrop < ratioSoft &&
        (landmarks.noseY     - calibration.noseY)     > camThreshold &&
        (landmarks.leftEarY  - calibration.leftEarY)  > camThreshold &&
        (landmarks.rightEarY - calibration.rightEarY) > camThreshold &&
        (camShoulderMidY     - calShoulderMidY)        > camThreshold;

    // Camera-confirmed low takes absolute priority: kill the accel-too-high latch
    // so it cannot fire during a noisy frame where _cameraTooLowActive briefly wavers.
    if (_cameraTooLowActive) _accelTooHighActive = false;

    final bool phoneTooLow  = _accelTooLowActive  || _cameraTooLowActive;
    // phoneTooLow (from any source) wins — once low is active, high is suppressed entirely.
    final bool phoneTooHigh = (_accelTooHighActive || cameraPhoneTooHigh) && !phoneTooLow;

    // ── Two-level suppression for body checks ─────────────────────────────────
    //
    // HARD extreme: an actual position violation is active, OR shoulders are
    // outside the reliable detection zone. Suppresses ALL body checks including
    // head tilt.
    // Person out of frame: shoulders too high/low (Y), or any landmark
    // actually outside the frame boundary (< 0 or > 1 in normalised space).
    // Do NOT use tight margins like 0.04 — off-centre users legitimately have
    // shoulder X values near the edges and would get false pose-lost triggers.
    final personOffScreen =
        landmarks.leftShoulderY  > 0.95 || landmarks.rightShoulderY  > 0.95 ||
        landmarks.leftShoulderY  < 0.07 || landmarks.rightShoulderY  < 0.07 ||
        landmarks.leftShoulderX  < 0.0  || landmarks.leftShoulderX  > 1.0 ||
        landmarks.rightShoulderX < 0.0  || landmarks.rightShoulderX > 1.0 ||
        landmarks.noseX < 0.0 || landmarks.noseX > 1.0 ||
        landmarks.noseY < 0.0;

    final hardExtreme =
        phoneTooHigh || phoneTooLow ||
        headRise || headDrop ||
        personOffScreen;

    // SOFT extreme: NTS is drifting toward a hard violation but hasn't fired
    // yet. Perspective distortion already makes shoulder width/height less
    // reliable here, so suppress shoulder checks. Head tilt (ear Y diff) is
    // much less affected by NTS drift, so it is NOT suppressed by soft extreme.
    final softExtreme = hardExtreme || ntsDrop > ratioSoft || ntsRise > ratioSoft;

    // ── Head tilt with hysteresis ─────────────────────────────────────────────
    // Triggers only on left/right tilt (ear height difference vs baseline).
    // Only suppressed by hardExtreme — soft NTS drift should not hide a real tilt.
    final baselineEarDiff = (calibration.leftEarY  - calibration.rightEarY).abs();
    final currentEarDiff  = (landmarks.leftEarY    - landmarks.rightEarY).abs();
    final headTiltExcess  = (currentEarDiff - baselineEarDiff).clamp(0.0, double.infinity);
    final headTiltPercent = (1.0 - headTiltExcess / (calibration.headTiltThreshold * 2.0)).clamp(0.0, 1.0) * 100;

    if (!hardExtreme && headTiltExcess > calibration.headTiltThreshold) {
      _headTiltActive = true;
    } else if (_headTiltActive &&
               (hardExtreme || headTiltExcess < calibration.headTiltThreshold * cameraHysteresisExit)) {
      _headTiltActive = false;
    }
    final headTilt = _headTiltActive;

    // ── Shoulder asymmetry with hysteresis ────────────────────────────────────
    // Triggers only when one shoulder Y moves higher/lower than the other vs baseline.
    // Suppressed by softExtreme and by head tilt (a tilted head shifts shoulder readings).
    // Entry 0.04, exit 0.02 — prevents per-frame flickering.
    final leftDelta  = landmarks.leftShoulderY  - calibration.leftShoulderY;
    final rightDelta = landmarks.rightShoulderY - calibration.rightShoulderY;
    final shoulderAsymmetryExcess = (leftDelta - rightDelta).abs();
    const shoulderYTrigger = 0.04;
    const shoulderYExit    = 0.02;
    const shoulderYZero    = 0.07;
    final shoulderSymmetryPercent = (1.0 - shoulderAsymmetryExcess / shoulderYZero).clamp(0.0, 1.0) * 100;

    if (!softExtreme && !headTilt && shoulderAsymmetryExcess > shoulderYTrigger) {
      _shoulderAsymmetryActive = true;
    } else if (_shoulderAsymmetryActive &&
               (softExtreme || headTilt || shoulderAsymmetryExcess < shoulderYExit)) {
      _shoulderAsymmetryActive = false;
    }
    final shoulderAsymmetry = _shoulderAsymmetryActive;

    // ── Shoulder rounding with hysteresis ─────────────────────────────────────
    // Triggers only when both shoulder Xs come closer together (width narrowed).
    // Suppressed by softExtreme and head tilt only — NOT by shoulder asymmetry,
    // because hunching (X narrowing) and unevenness (Y difference) are independent
    // axes that can co-occur. Pure Y-asymmetry never narrows width, so excluding
    // shoulderAsymmetry here does not re-introduce false positives.
    // Entry 0.04, exit 0.02 — prevents per-frame flickering.
    final widthNarrowed = (calibration.shoulderWidth - currentShoulderWidth).clamp(0.0, double.infinity);
    const roundingTrigger = 0.04;
    const roundingExit    = 0.02;
    const roundingZero    = 0.08;
    final shoulderRoundingPercent = (1.0 - widthNarrowed / roundingZero).clamp(0.0, 1.0) * 100;

    // headRise excluded: shoulder narrowing shrinks safeWidth, which inflates
    // NTS and causes a spurious headRise that would otherwise block detection.
    final shoulderRoundingBlock = phoneTooHigh || phoneTooLow || headDrop || personOffScreen;
    if (!shoulderRoundingBlock && !headTilt && widthNarrowed > roundingTrigger) {
      _shoulderRoundingActive = true;
    } else if (_shoulderRoundingActive &&
               (shoulderRoundingBlock || headTilt || widthNarrowed < roundingExit)) {
      _shoulderRoundingActive = false;
    }
    final shoulderRounding = _shoulderRoundingActive;

    final violations = (shoulderAsymmetry ? 1 : 0) +
        (headTilt ? 1 : 0) +
        (shoulderRounding ? 1 : 0) +
        (headRise ? 1 : 0) +
        (headDrop ? 1 : 0) +
        (phoneTooLow ? 1 : 0) +
        (phoneTooHigh ? 1 : 0);

    return PostureAnalysisResult(
      status: PostureStatus.fromViolationCount(violations),
      shoulderAsymmetry: shoulderAsymmetry,
      headTilt: headTilt,
      shoulderRounding: shoulderRounding,
      headRise: headRise,
      headDrop: headDrop,
      phoneTooLow: phoneTooLow,
      phoneTooHigh: phoneTooHigh,
      personOffScreen: personOffScreen,
      shoulderSymmetryPercent: shoulderSymmetryPercent,
      headTiltPercent: headTiltPercent,
      shoulderRoundingPercent: shoulderRoundingPercent,
      headRisePercent: headRisePercent,
      headDropPercent: headDropPercent,
      phoneTooLowPercent: phoneTooLowPercent,
      phoneTooHighPercent: phoneTooHighPercent,
    );
  }
}
