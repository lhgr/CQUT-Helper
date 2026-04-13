import 'dart:convert';
import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/utils/schedule_notice_metrics.dart';
import 'package:cqut_helper/utils/schedule_update_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleUpdateManager {
  final ScheduleController controller;
  bool _checkInFlight = false;
  static const String _pendingKeyPrefix = 'schedule_pending_changes_';

  ScheduleUpdateManager({required this.controller});

  void dispose() {}

  Future<List<ScheduleWeekChange>> checkForUpdates(
    ScheduleData currentData,
  ) async {
    final result = await _checkForUpdatesInternal(
      currentData,
      runType: 'foreground_manual',
    );
    return result.changes;
  }

  Future<
    ({
      List<ScheduleWeekChange> changes,
      bool hadFailures,
      int failureDelta,
      bool apiClosed,
      int changedNotices,
      int affectedWeeks,
    })
  >
  _checkForUpdatesInternal(
    ScheduleData currentData, {
    required String runType,
  }) async {
    if (_checkInFlight) {
      return (
        changes: const <ScheduleWeekChange>[],
        hadFailures: false,
        failureDelta: 0,
        apiClosed: false,
        changedNotices: 0,
        affectedWeeks: 0,
      );
    }
    _checkInFlight = true;
    final startAt = DateTime.now();
    final failuresBefore = await ScheduleUpdateLog.failureCounter();
    List<ScheduleWeekChange> changes = const <ScheduleWeekChange>[];
    int changedNotices = 0;
    int affectedWeeks = 0;
    bool apiClosed = false;
    Object? error;
    StackTrace? stackTrace;
    int failureDelta = 0;
    bool hadFailures = false;
    try {
      final pipeline = ScheduleNoticeRefreshPipeline(
        refreshWeek: (weekNum, yearTerm) {
          return controller.ensureWeekLoaded(
            weekNum,
            yearTerm,
            forceRefresh: true,
            updateLastViewed: false,
          );
        },
      );
      final result = await pipeline.run(currentData: currentData);
      changes = result.changes;
      changedNotices = result.changedNoticeCount;
      affectedWeeks = result.affectedWeeks.length;
      apiClosed = result.apiClosed;
      if (changes.isNotEmpty) {
        ScheduleUpdateIntents.requestScheduleUpdated();
      }
    } catch (e, st) {
      error = e;
      stackTrace = st;
      await ScheduleUpdateLog.appendFailure({
        'at': DateTime.now().millisecondsSinceEpoch,
        'scope': runType,
        'error': e.toString(),
      });
    } finally {
      final failuresAfter = await ScheduleUpdateLog.failureCounter();
      failureDelta = failuresAfter - failuresBefore;
      hadFailures = !apiClosed && (error != null || failureDelta > 0);
      final durationMs = DateTime.now().difference(startAt).inMilliseconds;
      final metricText = await ScheduleNoticeMetrics.record(
        ScheduleNoticeMetricsRecord(
          runType: runType,
          success: !hadFailures && !apiClosed,
          degraded: false,
          apiClosed: apiClosed,
          changeCount: changedNotices,
          affectedWeeks: affectedWeeks,
          durationMs: durationMs,
          failureStreak: 0,
        ),
      );
      await ScheduleUpdateLog.appendRun({
        'at': DateTime.now().millisecondsSinceEpoch,
        'type': runType,
        'pollType': 'notice',
        'changedNotices': changedNotices,
        'affectedWeeks': affectedWeeks,
        'weeksChanged': changes.length,
        'apiClosed': apiClosed,
        'durationMs': durationMs,
        'hadFailures': hadFailures,
        'failureDelta': failureDelta,
        'metricsProm': metricText,
      });
      if (stackTrace != null) {
        await ScheduleUpdateLog.appendRun({
          'at': DateTime.now().millisecondsSinceEpoch,
          'type': '${runType}_exception',
          'error': error.toString(),
          'stack': stackTrace.toString(),
        });
      }
      _checkInFlight = false;
    }
    return (
      changes: changes,
      hadFailures: hadFailures,
      failureDelta: failureDelta,
      apiClosed: apiClosed,
      changedNotices: changedNotices,
      affectedWeeks: affectedWeeks,
    );
  }

  Future<({String? yearTerm, List<ScheduleWeekChange> changes})>
  checkPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('account');
    if (userId == null || userId.trim().isEmpty) {
      return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
    }

    final key = '$_pendingKeyPrefix$userId';
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
    }
    await prefs.remove(key);

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
      }
      final yearTerm = (decoded['yearTerm'] ?? '').toString().trim();
      final items = decoded['changes'];
      if (items is! List) {
        return (
          yearTerm: yearTerm.isEmpty ? null : yearTerm,
          changes: const <ScheduleWeekChange>[],
        );
      }

      final changes = <ScheduleWeekChange>[];
      for (final it in items) {
        if (it is! Map) continue;
        final weekNum = (it['weekNum'] ?? '').toString();
        final linesRaw = it['lines'];
        final lines = linesRaw is List
            ? linesRaw.map((e) => e.toString()).toList()
            : const <String>[];
        if (weekNum.isEmpty) continue;
        changes.add(ScheduleWeekChange(weekNum: weekNum, lines: lines));
      }
      return (yearTerm: yearTerm.isEmpty ? null : yearTerm, changes: changes);
    } catch (_) {
      return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
    }
  }
}
