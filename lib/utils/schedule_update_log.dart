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

  static Future<void> appendRun(
    Map<String, dynamic> item, {
    Object? error,
    StackTrace? stackTrace,
  }) async {
    final fields = _sanitizeForRuntime(item);
    final skipped = item['apiClosed'] == true || item['skip_reason'] != null;
    AppLogger.I.logOperationOutcome(
      'ScheduleUpdate',
      'run',
      outcome: item['hadFailures'] == true
          ? 'failed'
          : skipped
          ? 'skipped'
          : 'succeeded',
      error: error,
      stackTrace: stackTrace,
      fields: {
        ...fields,
        'stage': 'schedule_update',
        'reason':
            item['skip_reason'] ??
            (item['apiClosed'] == true
                ? 'api_closed'
                : item['hadFailures'] == true
                ? 'refresh_failed'
                : 'completed'),
      },
    );
  }

  static Future<void> appendFailure(
    Map<String, dynamic> item, {
    Object? error,
    StackTrace? stackTrace,
    bool recordFailure = true,
  }) async {
    // This counter is a business signal used by the run result. Historical
    // diagnostic payloads belong only to the bounded diagnostic store.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final counter = (prefs.getInt(_failureCounterKey) ?? 0) + 1;
      await prefs.setInt(_failureCounterKey, counter);
    } catch (_) {}
    if (recordFailure && error != null) {
      AppLogger.I.logOperationFailure(
        'ScheduleUpdate',
        'update failed',
        error: error,
        stackTrace: stackTrace,
        fields: {..._sanitizeForRuntime(item), 'stage': 'schedule_update'},
      );
    }
  }
}
