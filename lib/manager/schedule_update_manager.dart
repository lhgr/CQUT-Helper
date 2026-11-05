import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/manager/schedule_update_effects.dart';
import 'package:cqut_helper/manager/schedule_update_result.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/utils/app_logger.dart';

class ScheduleUpdateManager {
  final ScheduleController controller;
  bool _checkInFlight = false;

  ScheduleUpdateManager({required this.controller});

  void dispose() {}

  Future<List<ScheduleWeekChange>> checkForUpdates(
    ScheduleData currentData, {
    String trigger = 'foreground_manual',
  }) => AppLogger.I.runWithTraceIdAsync(
    AppLogger.I.currentTraceId ?? AppLogger.I.newTraceId(),
    () async {
      final result = await _checkForUpdatesInternal(
        currentData,
        runType: trigger,
      );
      return result.changes;
    },
  );

  Future<ScheduleUpdateRunResult> _checkForUpdatesInternal(
    ScheduleData currentData, {
    required String runType,
  }) async {
    if (_checkInFlight) {
      AppLogger.I.logOperationOutcome(
        'ScheduleUpdate',
        'notice check skipped',
        outcome: 'skipped',
        fields: {
          'stage': 'schedule_update',
          'trigger': runType,
          'reason': 'already_running',
        },
      );
      return const ScheduleUpdateRunResult.empty();
    }
    _checkInFlight = true;
    final startAt = DateTime.now();
    var failuresBefore = 0;
    var summary = const ScheduleUpdatePipelineSummary.empty();
    Object? error;
    StackTrace? stackTrace;
    ScheduleUpdateRunResult finalized;
    final pipeline = ScheduleNoticeRefreshPipeline(
      refreshWeek: (weekNum, yearTerm) async {
        await controller.ensureWeekLoaded(
          weekNum,
          yearTerm,
          forceRefresh: true,
          updateLastViewed: false,
          rethrowOnFailure: true,
        );
      },
    );
    try {
      failuresBefore = await loadScheduleUpdateFailureCounter();
      final result = await pipeline.run(currentData: currentData);
      summary = ScheduleUpdatePipelineSummary.fromRefreshResult(result);
      requestScheduleUpdatedIfNeeded(summary.changes);
    } catch (e, st) {
      error = e;
      stackTrace = st;
      await appendScheduleUpdateFailure(
        runType: runType,
        error: e,
        stackTrace: st,
      );
    } finally {
      try {
        finalized = await finalizeScheduleUpdateRun(
          runType: runType,
          startAt: startAt,
          failuresBefore: failuresBefore,
          summary: summary,
          error: error,
          stackTrace: stackTrace,
          diagnosticFields: pipeline.diagnosticProgress,
        );
      } finally {
        _checkInFlight = false;
      }
    }
    return finalized;
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
