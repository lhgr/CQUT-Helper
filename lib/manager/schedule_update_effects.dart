import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/manager/schedule_update_result.dart';
import 'package:cqut_helper/manager/schedule_update_worker_state_store.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/utils/schedule_notice_metrics.dart';
import 'package:cqut_helper/utils/schedule_update_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<int> loadScheduleUpdateFailureCounter() {
  return ScheduleUpdateLog.failureCounter();
}

void requestScheduleUpdatedIfNeeded(List<ScheduleWeekChange> changes) {
  if (changes.isEmpty) return;
  ScheduleUpdateIntents.requestScheduleUpdated();
}

Future<void> appendScheduleUpdateFailure({
  required String runType,
  required Object error,
}) {
  return ScheduleUpdateLog.appendFailure({
    'at': DateTime.now().millisecondsSinceEpoch,
    'scope': runType,
    'error': error.toString(),
  });
}

Future<ScheduleUpdateRunResult> finalizeScheduleUpdateRun({
  required String runType,
  required DateTime startAt,
  required int failuresBefore,
  required ScheduleUpdatePipelineSummary summary,
  required Object? error,
  required StackTrace? stackTrace,
}) async {
  final failuresAfter = await ScheduleUpdateLog.failureCounter();
  final result = buildScheduleUpdateRunResult(
    summary: summary,
    error: error,
    failuresBefore: failuresBefore,
    failuresAfter: failuresAfter,
  );
  final durationMs = DateTime.now().difference(startAt).inMilliseconds;
  await ScheduleNoticeMetrics.record(
    ScheduleNoticeMetricsRecord(
      runType: runType,
      success: !result.hadFailures && !result.apiClosed,
      degraded: false,
      apiClosed: result.apiClosed,
      changeCount: result.changedNotices,
      affectedWeeks: result.affectedWeeks,
      durationMs: durationMs,
      failureStreak: 0,
    ),
  );
  await ScheduleUpdateLog.appendRun({
    'at': DateTime.now().millisecondsSinceEpoch,
    'type': runType,
    'pollType': 'notice',
    'changedNotices': result.changedNotices,
    'affectedWeeks': result.affectedWeeks,
    'weeksChanged': result.changes.length,
    'apiClosed': result.apiClosed,
    'durationMs': durationMs,
    'hadFailures': result.hadFailures,
    'failureDelta': result.failureDelta,
  });
  if (stackTrace != null) {
    await ScheduleUpdateLog.appendRun({
      'at': DateTime.now().millisecondsSinceEpoch,
      'type': '${runType}_exception',
      'error': error.toString(),
      'stack': stackTrace.toString(),
    });
  }
  return result;
}

Future<String?> consumeScheduleUpdatePendingRawForCurrentUser() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getString('account');
  if (userId == null || userId.trim().isEmpty) return null;

  final key = scheduleUpdateWorkerPendingKeyForUser(userId);
  final raw = prefs.getString(key);
  if (raw == null || raw.trim().isEmpty) {
    return null;
  }
  await prefs.remove(key);
  return raw;
}
