import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import '../models/device_metrics_summary.dart';
import '../models/posture_status.dart';
import '../models/session_summary.dart';
import 'device_metrics_service.dart';

class DatabaseService {
  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'postureguard.db');

    return openDatabase(
      path,
      version: 5,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createDeviceMetricsTable(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE sessions ADD COLUMN variant TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE sessions ADD COLUMN user_id TEXT');
        }
        if (oldVersion < 5) await _createUploadQueueTable(db);
      },
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE posture_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            status INTEGER NOT NULL
          )
        ''');

        await db.execute('''
          CREATE TABLE sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id TEXT NOT NULL UNIQUE,
            date TEXT NOT NULL,
            duration_seconds INTEGER NOT NULL,
            good_posture_percent REAL NOT NULL,
            longest_streak INTEGER NOT NULL,
            worst_moment_timestamp INTEGER,
            variant TEXT,
            user_id TEXT
          )
        ''');

        await _createDeviceMetricsTable(db);
        await _createUploadQueueTable(db);
      },
    );
  }

  /// Battery / CPU / temperature readings taken during a session. Kept apart
  /// from posture_events on purpose: those rows are a strict 1 Hz series the
  /// integrity checker validates, while these are sampled far less often.
  static Future<void> _createDeviceMetricsTable(Database db) async {
    await db.execute('''
      CREATE TABLE device_metrics (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        battery_percent REAL,
        battery_temperature_c REAL,
        is_charging INTEGER NOT NULL,
        thermal_status TEXT NOT NULL,
        cpu_percent REAL,
        cpu_cores INTEGER,
        is_screen_on INTEGER NOT NULL,
        is_power_save INTEGER NOT NULL,
        app_state TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_device_metrics_session ON device_metrics(session_id)');
  }

  // ─── Per-second event logging ───

  static Future<void> logEvent({
    required String sessionId,
    required PostureStatus status,
  }) async {
    final db = await database;
    await db.insert('posture_events', {
      'session_id': sessionId,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'status': status.value,
    });
  }

  /// One row per finished session waiting to reach the server. Rows are
  /// never deleted: `sent` and `blocked` rows are the record of what happened.
  static Future<void> _createUploadQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE upload_queue (
        session_id TEXT PRIMARY KEY,
        status TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        queued_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');
  }

  // ─── Upload queue ───

  /// Queue a finished session for upload. Re-queuing an existing session is a
  /// no-op, so it's safe to call more than once.
  static Future<void> enqueueUpload(String sessionId) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      'upload_queue',
      {
        'session_id': sessionId,
        'status': 'pending',
        'attempts': 0,
        'queued_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  static Future<List<String>> getPendingUploads() async {
    final db = await database;
    final rows = await db.query(
      'upload_queue',
      columns: ['session_id'],
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'queued_at ASC',
    );
    return rows.map((r) => r['session_id'] as String).toList();
  }

  /// [status] is `pending` (retry later), `sent`, or `blocked` (failed the
  /// integrity check; kept on the phone, never sent).
  static Future<void> updateUpload(
    String sessionId, {
    required String status,
    String? error,
    bool countAttempt = false,
  }) async {
    final db = await database;
    await db.rawUpdate(
      'UPDATE upload_queue SET status = ?, last_error = ?, updated_at = ?, '
      'attempts = attempts + ? WHERE session_id = ?',
      [status, error, DateTime.now().millisecondsSinceEpoch, countAttempt ? 1 : 0, sessionId],
    );
  }

  static Future<Map<String, int>> getUploadCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT status, COUNT(*) AS n FROM upload_queue GROUP BY status');
    return {for (final r in rows) r['status'] as String: r['n'] as int};
  }

  // ─── Device resource logging ───

  /// [appState] is `foreground`, `pip` (user is in another app) or
  /// `background` (PiP closed, accelerometer-only).
  static Future<void> logDeviceMetrics({
    required String sessionId,
    required DeviceMetricsSample sample,
    required String appState,
  }) async {
    final db = await database;
    await db.insert('device_metrics', {
      'session_id': sessionId,
      'timestamp': sample.timestamp.millisecondsSinceEpoch,
      'battery_percent': sample.batteryPercent,
      'battery_temperature_c': sample.batteryTemperatureC,
      'is_charging': sample.isCharging ? 1 : 0,
      'thermal_status': sample.thermalStatus,
      'cpu_percent': sample.cpuPercent,
      'cpu_cores': sample.cpuCores,
      'is_screen_on': sample.isScreenOn ? 1 : 0,
      'is_power_save': sample.isPowerSaveMode ? 1 : 0,
      'app_state': appState,
    });
  }

  static Future<List<Map<String, dynamic>>> getSessionDeviceMetrics(
      String sessionId) async {
    final db = await database;
    return db.query(
      'device_metrics',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  static Future<DeviceMetricsSummary> getDeviceMetricsSummary(
      String sessionId) async {
    return DeviceMetricsSummary.fromRows(
        sessionId, await getSessionDeviceMetrics(sessionId));
  }

  // ─── Session summary computation ───

  static Future<SessionSummary> endSession(
    String sessionId, {
    required String variant,
    required String userId,
  }) async {
    final db = await database;

    final events = await db.query(
      'posture_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );

    final totalRecords = events.length;
    if (totalRecords == 0) {
      final summary = SessionSummary(
        sessionId: sessionId,
        date: DateTime.now(),
        durationSeconds: 0,
        goodPosturePercent: 0,
        longestStreakSeconds: 0,
        variant: variant,
        userId: userId,
      );
      await _saveSession(summary);
      return summary;
    }

    // Duration
    final firstTs = events.first['timestamp'] as int;
    final lastTs = events.last['timestamp'] as int;
    final durationSeconds = ((lastTs - firstTs) / 1000).round().clamp(1, 999999);

    // Good posture percentage
    final goodCount = events.where((e) => e['status'] == 0).length;
    final goodPercent = (goodCount / totalRecords) * 100;

    // Longest consecutive good streak (in seconds)
    int longestStreak = 0;
    int currentStreak = 0;
    for (final event in events) {
      if (event['status'] == 0) {
        currentStreak++;
        if (currentStreak > longestStreak) longestStreak = currentStreak;
      } else {
        currentStreak = 0;
      }
    }

    // Worst moment: start of the longest consecutive bad streak
    int longestBadStreak = 0;
    int currentBadStreak = 0;
    int worstMomentIdx = 0;
    for (int i = 0; i < events.length; i++) {
      if (events[i]['status'] == 2) {
        currentBadStreak++;
        if (currentBadStreak > longestBadStreak) {
          longestBadStreak = currentBadStreak;
          worstMomentIdx = i - currentBadStreak + 1;
        }
      } else {
        currentBadStreak = 0;
      }
    }

    DateTime? worstMoment;
    if (longestBadStreak > 0) {
      worstMoment = DateTime.fromMillisecondsSinceEpoch(
        events[worstMomentIdx]['timestamp'] as int,
      );
    }

    final summary = SessionSummary(
      sessionId: sessionId,
      date: DateTime.now(),
      durationSeconds: durationSeconds,
      goodPosturePercent: goodPercent,
      longestStreakSeconds: longestStreak,
      worstMomentTimestamp: worstMoment,
      variant: variant,
      userId: userId,
    );

    await _saveSession(summary);
    return summary;
  }

  static Future<void> _saveSession(SessionSummary summary) async {
    final db = await database;
    await db.insert(
      'sessions',
      summary.toMap()..remove('id'),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ─── Query methods ───

  static Future<List<SessionSummary>> getAllSessions() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'date DESC');
    return rows.map((r) => SessionSummary.fromMap(r)).toList();
  }

  static Future<SessionSummary?> getLatestSession() async {
    final db = await database;
    final rows = await db.query('sessions', orderBy: 'date DESC', limit: 1);
    if (rows.isEmpty) return null;
    return SessionSummary.fromMap(rows.first);
  }

  /// Get per-second status events for a session (for heatmap chart).
  static Future<List<Map<String, dynamic>>> getSessionEvents(
      String sessionId) async {
    final db = await database;
    return db.query(
      'posture_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'timestamp ASC',
    );
  }

  /// Get a session's events in the order they were *written*, not the order
  /// their timestamps imply.
  ///
  /// [getSessionEvents] sorts by timestamp, which silently repairs a clock
  /// rewind: rows recorded out of order come back looking monotonic. The
  /// integrity check needs to see the sequence as it was actually recorded,
  /// so it orders by the autoincrement id instead.
  static Future<List<Map<String, dynamic>>> getSessionEventsInWriteOrder(
      String sessionId) async {
    final db = await database;
    return db.query(
      'posture_events',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 'id ASC',
    );
  }

  /// Look up a single stored session summary. Returns null if absent.
  static Future<SessionSummary?> getSession(String sessionId) async {
    final db = await database;
    final rows = await db.query(
      'sessions',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return SessionSummary.fromMap(rows.first);
  }
}
