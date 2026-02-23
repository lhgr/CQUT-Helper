import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ScheduleUpdateLog {
  static const String _runsKey = 'schedule_update_runs';
  static const String _failuresKey = 'schedule_update_failures';

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
  }
}

