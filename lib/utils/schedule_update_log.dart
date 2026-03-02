import 'dart:convert';

import 'package:cqut/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleUpdateLog {
  static const String _runsKey = 'schedule_update_runs';
  static const String _failuresKey = 'schedule_update_failures';
  static const String _failureCounterKey = 'schedule_update_failure_counter_v1';

  static Future<int> failureCounter() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_failureCounterKey) ?? 0;
  }

  static Map<String, Object?> _sanitizeForRuntime(Map<String, dynamic> item) {
    if (item.isEmpty) return const {};
    final out = <String, Object?>{};
    for (final e in item.entries) {
      final k = e.key;
      if (k == 'userId' ||
          k == 'account' ||
          k == 'password' ||
          k == 'encryptedPassword' ||
          k == 'token' ||
          k == 'cookie') {
        continue;
      }
      out[k] = e.value;
    }
    return out;
  }

  static Future<void> appendRun(Map<String, dynamic> item, {int max = 80}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_runsKey);

    final list = <dynamic>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) list.addAll(decoded);
      } catch (_) {}
    }

    list.add(item);
    if (list.length > max) {
      list.removeRange(0, list.length - max);
    }

    await prefs.setString(_runsKey, json.encode(list));

    final fields = _sanitizeForRuntime(item);
    if (fields.isNotEmpty) {
      AppLogger.I.info('ScheduleUpdate', 'run', fields: fields);
    } else {
      AppLogger.I.info('ScheduleUpdate', 'run');
    }
  }

  static Future<void> appendFailure(
    Map<String, dynamic> item, {
    int max = 120,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_failuresKey);

    final list = <dynamic>[];
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(raw);
        if (decoded is List) list.addAll(decoded);
      } catch (_) {}
    }

    list.add(item);
    if (list.length > max) {
      list.removeRange(0, list.length - max);
    }

    await prefs.setString(_failuresKey, json.encode(list));

    final counter = (prefs.getInt(_failureCounterKey) ?? 0) + 1;
    await prefs.setInt(_failureCounterKey, counter);

    final fields = _sanitizeForRuntime(item);
    if (fields.isNotEmpty) {
      AppLogger.I.warn('ScheduleUpdate', 'failure', fields: fields);
    } else {
      AppLogger.I.warn('ScheduleUpdate', 'failure');
    }
  }
}

