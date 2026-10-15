import 'package:cqut_helper/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleUpdateLog {
  static const String _failureCounterKey = 'schedule_update_failure_counter_v1';

  static Future<int> failureCounter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return prefs.getInt(_failureCounterKey) ?? 0;
    } catch (_) {
      return 0;
    }
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
          k == 'cookie' ||
          k == 'error' ||
          k == 'stack') {
        continue;
      }
      out[k] = e.value;
    }
    return out;
  }

  static Future<void> appendRun(Map<String, dynamic> item) async {
    final fields = _sanitizeForRuntime(item);
    AppLogger.I.info(
      'ScheduleUpdate',
      'run',
      fields: {
        ...fields,
        'stage': 'schedule_update',
        'diagnostic_kind': 'operation',
        'outcome': item['hadFailures'] == true ? 'failed' : 'completed',
      },
    );
  }

  static Future<void> appendFailure(
    Map<String, dynamic> item, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    // This counter is a business signal used by the run result. Historical
    // diagnostic payloads belong only to the bounded diagnostic store.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final counter = (prefs.getInt(_failureCounterKey) ?? 0) + 1;
      await prefs.setInt(_failureCounterKey, counter);
    } catch (_) {}
    final fields = _sanitizeForRuntime(item);
    if (error != null) {
      AppLogger.I.logOperationFailure(
        'ScheduleUpdate',
        'update failed',
        error: error,
        stackTrace: stackTrace,
        fields: {...fields, 'stage': 'schedule_update', 'outcome': 'failed'},
      );
      return;
    }
    AppLogger.I.info(
      'ScheduleUpdate',
      'update outcome',
      fields: {
        ...fields,
        'stage': 'schedule_update',
        'diagnostic_kind': 'operation',
        'outcome': 'failed',
        if (item['error'] is String) 'reason': item['error'],
      },
    );
  }
}
