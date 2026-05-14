import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/manager/schedule_update_effects.dart';
import 'package:cqut_helper/manager/schedule_update_result.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';

class ScheduleUpdateManager {
  final ScheduleController controller;
  bool _checkInFlight = false;

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
      const result = ScheduleUpdateRunResult.empty();
      return (
        changes: result.changes,
        hadFailures: result.hadFailures,
        failureDelta: result.failureDelta,
        apiClosed: result.apiClosed,
        changedNotices: result.changedNotices,
        affectedWeeks: result.affectedWeeks,
      );
    }
    _checkInFlight = true;
    final startAt = DateTime.now();
    final failuresBefore = await loadScheduleUpdateFailureCounter();
    var summary = const ScheduleUpdatePipelineSummary.empty();
    Object? error;
    StackTrace? stackTrace;
    ScheduleUpdateRunResult? finalized;
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
      summary = ScheduleUpdatePipelineSummary.fromRefreshResult(result);
      requestScheduleUpdatedIfNeeded(summary.changes);
    } catch (e, st) {
      error = e;
      stackTrace = st;
      await appendScheduleUpdateFailure(runType: runType, error: e);
    } finally {
      finalized = await finalizeScheduleUpdateRun(
        runType: runType,
        startAt: startAt,
        failuresBefore: failuresBefore,
        summary: summary,
        error: error,
        stackTrace: stackTrace,
      );
      _checkInFlight = false;
    }
    final result = finalized;
    return (
      changes: result.changes,
      hadFailures: result.hadFailures,
      failureDelta: result.failureDelta,
      apiClosed: result.apiClosed,
      changedNotices: result.changedNotices,
      affectedWeeks: result.affectedWeeks,
    );
  }

  Future<({String? yearTerm, List<ScheduleWeekChange> changes})>
  checkPendingChanges() async {
    final raw = await consumeScheduleUpdatePendingRawForCurrentUser();
    if (raw == null) {
      return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
    }

    final result = parseScheduleUpdatePendingPayload(raw);
    return (yearTerm: result.yearTerm, changes: result.changes);
  }
}
