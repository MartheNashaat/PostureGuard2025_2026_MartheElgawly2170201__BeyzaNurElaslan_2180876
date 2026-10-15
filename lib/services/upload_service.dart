import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';
import 'database_service.dart';
import 'telemetry_integrity_gate.dart';
import 'upload_payload.dart';

/// Sends finished sessions to the study server (`study/API_SCHEMA.md`).
///
/// Sessions are queued in SQLite when they end and sent by [flush], which runs
/// after every session, on app start and when the home screen opens. Anything
/// that fails — no network, server down, non-2xx — stays `pending` and is
/// retried on the next flush. The server treats (user_id, session_id) as
/// unique, so a retry after a lost response can't create a duplicate.
class UploadService {
  static const MethodChannel _channel = MethodChannel('com.postureguard/overlay');
  static const _deviceIdKey = 'device_id';
  static const _timeout = Duration(seconds: 30);

  static bool _flushing = false;
  static DeviceInfo? _deviceInfo;

  /// Queue a just-finished session and try to send everything pending.
  static Future<void> enqueueAndFlush(String sessionId) async {
    await DatabaseService.enqueueUpload(sessionId);
    unawaited(flush());
  }

  static Future<void> flush() async {
    if (_flushing) return;
    if (AppConfig.apiBaseUrl.isEmpty) {
      debugPrint('UploadService: API_BASE_URL not set; sessions stay queued.');
      return;
    }
    _flushing = true;
    try {
      final pending = await DatabaseService.getPendingUploads();
      if (pending.isEmpty) return;
      final device = await _getDeviceInfo();
      final deviceId = await _getDeviceId();
      final uri = Uri.parse('${AppConfig.apiBaseUrl}${AppConfig.sessionsPath}');

      for (final sessionId in pending) {
        final gate = await TelemetryIntegrityGate.buildUploadPayload(
          sessionId,
          device: device,
        );
        if (gate.isBlocked) {
          // Kept on the phone, never sent; the report says why.
          await DatabaseService.updateUpload(sessionId,
              status: 'blocked', error: gate.report.toString());
          continue;
        }

        try {
          final response = await http
              .post(
                uri,
                headers: {
                  'Content-Type': 'application/json',
                  'X-Device-Id': deviceId,
                },
                body: jsonEncode(gate.payload),
              )
              .timeout(_timeout);
          if (response.statusCode >= 200 && response.statusCode < 300) {
            await DatabaseService.updateUpload(sessionId,
                status: 'sent', countAttempt: true);
          } else {
            await DatabaseService.updateUpload(sessionId,
                status: 'pending',
                error: 'HTTP ${response.statusCode}',
                countAttempt: true);
          }
        } catch (e) {
          // Offline or unreachable: the rest would fail the same way.
          await DatabaseService.updateUpload(sessionId,
              status: 'pending', error: '$e', countAttempt: true);
          break;
        }
      }
    } catch (e) {
      debugPrint('UploadService: flush failed: $e');
    } finally {
      _flushing = false;
    }
  }

  static Future<DeviceInfo> _getDeviceInfo() async {
    if (_deviceInfo != null) return _deviceInfo!;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('getDeviceInfo');
      _deviceInfo = DeviceInfo.fromMap(raw ?? const {});
    } catch (e) {
      debugPrint('UploadService: device info unavailable: $e');
      _deviceInfo = const DeviceInfo();
    }
    return _deviceInfo!;
  }

  /// Random per-install identifier for the `X-Device-Id` header. Not tied to
  /// the hardware, so it identifies an install, not a person.
  static Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceIdKey);
    if (id == null) {
      final rnd = Random.secure();
      id = List.generate(16, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString(_deviceIdKey, id);
    }
    return id;
  }
}
