import '../models/integrity_report.dart';
import 'database_service.dart';
import 'telemetry_integrity_service.dart';

/// Outcome of asking the gate for a session's upload payload.
///
/// [payload] is non-null only when the session passed validation — that is
/// the enforcement: a caller that wants something to send has to go through
/// a check to get it, and cannot skip it by accident.
class UploadGateResult {
  final IntegrityReport report;
  final Map<String, dynamic>? payload;

  const UploadGateResult._(this.report, this.payload);

  /// True when the session is clear to send.
  bool get isCleared => payload != null;

  /// True when the session was held back. Inspect [report] for why.
  bool get isBlocked => payload == null;
}

/// The "trust before upload" entry point: validates locally stored session
/// data against the device database before any of it leaves the device.
///
/// This is the only integrity code that touches sqflite. The decision logic
/// lives in [TelemetryIntegrityService], which is pure and unit-tested.
///
/// There is no sync layer in PostureGuard yet. When one is added, it must
/// obtain its request body from [buildUploadPayload] rather than querying
/// `DatabaseService` directly — that is what keeps the check unskippable.
class TelemetryIntegrityGate {
  /// Validate one stored session, reading both its events and its summary.
  ///
  /// Events are read in write order so that a clock rewind during recording
  /// is actually visible; see
  /// [DatabaseService.getSessionEventsInWriteOrder].
  static Future<IntegrityReport> validateStoredSession(
    String sessionId, {
    Duration expectedInterval =
        TelemetryIntegrityService.defaultExpectedInterval,
    double gapTolerance = TelemetryIntegrityService.defaultGapTolerance,
  }) async {
    final events =
        await DatabaseService.getSessionEventsInWriteOrder(sessionId);
    final summary = await DatabaseService.getSession(sessionId);

    return TelemetryIntegrityService.validateSession(
      sessionId: sessionId,
      events: events,
      summary: summary,
      expectedInterval: expectedInterval,
      gapTolerance: gapTolerance,
    );
  }

  /// Validate every stored session and return the reports, newest first.
  ///
  /// Use this for a "review flagged sessions" screen or a pre-sync sweep.
  static Future<List<IntegrityReport>> validateAllStoredSessions({
    Duration expectedInterval =
        TelemetryIntegrityService.defaultExpectedInterval,
    double gapTolerance = TelemetryIntegrityService.defaultGapTolerance,
  }) async {
    final sessions = await DatabaseService.getAllSessions();
    final reports = <IntegrityReport>[];
    for (final session in sessions) {
      reports.add(await validateStoredSession(
        session.sessionId,
        expectedInterval: expectedInterval,
        gapTolerance: gapTolerance,
      ));
    }
    return reports;
  }

  /// Validate a session and, only if it is clean, build the body to upload.
  ///
  /// A blocked session is left completely untouched on disk — nothing is
  /// deleted, rewritten, or marked. Deciding what to do with it is the
  /// caller's job; see the strategy notes in the accompanying documentation.
  static Future<UploadGateResult> buildUploadPayload(
    String sessionId, {
    Duration expectedInterval =
        TelemetryIntegrityService.defaultExpectedInterval,
    double gapTolerance = TelemetryIntegrityService.defaultGapTolerance,
  }) async {
    final report = await validateStoredSession(
      sessionId,
      expectedInterval: expectedInterval,
      gapTolerance: gapTolerance,
    );

    if (!report.isValid) {
      return UploadGateResult._(report, null);
    }

    final summary = await DatabaseService.getSession(sessionId);
    final events =
        await DatabaseService.getSessionEventsInWriteOrder(sessionId);

    return UploadGateResult._(report, {
      'session_id': sessionId,
      'summary': summary?.toMap(),
      'events': events
          .map((e) => {
                'timestamp': e['timestamp'],
                'status': e['status'],
              })
          .toList(),
      // Ship the verdict alongside the data so the server can see which
      // client-side rules the payload was accepted under.
      'integrity': report.toMap(),
    });
  }
}
