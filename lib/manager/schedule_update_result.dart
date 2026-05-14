import 'dart:convert';

import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';

class ScheduleUpdatePipelineSummary {
  final List<ScheduleWeekChange> changes;
  final int changedNotices;
  final int affectedWeeks;
  final bool apiClosed;

  const ScheduleUpdatePipelineSummary({
    required this.changes,
    required this.changedNotices,
    required this.affectedWeeks,
    required this.apiClosed,
  });

  const ScheduleUpdatePipelineSummary.empty()
    : changes = const <ScheduleWeekChange>[],
      changedNotices = 0,
      affectedWeeks = 0,
      apiClosed = false;

  factory ScheduleUpdatePipelineSummary.fromRefreshResult(
    ScheduleNoticeRefreshResult result,
  ) {
    return ScheduleUpdatePipelineSummary(
      changes: result.changes,
      changedNotices: result.changedNoticeCount,
      affectedWeeks: result.affectedWeeks.length,
      apiClosed: result.apiClosed,
    );
  }
}

class ScheduleUpdateRunResult {
  final List<ScheduleWeekChange> changes;
  final bool hadFailures;
  final int failureDelta;
  final bool apiClosed;
  final int changedNotices;
  final int affectedWeeks;

  const ScheduleUpdateRunResult({
    required this.changes,
    required this.hadFailures,
    required this.failureDelta,
    required this.apiClosed,
    required this.changedNotices,
    required this.affectedWeeks,
  });

  const ScheduleUpdateRunResult.empty()
    : changes = const <ScheduleWeekChange>[],
      hadFailures = false,
      failureDelta = 0,
      apiClosed = false,
      changedNotices = 0,
      affectedWeeks = 0;
}

ScheduleUpdateRunResult buildScheduleUpdateRunResult({
  required ScheduleUpdatePipelineSummary summary,
  required Object? error,
  required int failuresBefore,
  required int failuresAfter,
}) {
  final failureDelta = failuresAfter - failuresBefore;
  final hadFailures = !summary.apiClosed && (error != null || failureDelta > 0);
  return ScheduleUpdateRunResult(
    changes: summary.changes,
    hadFailures: hadFailures,
    failureDelta: failureDelta,
    apiClosed: summary.apiClosed,
    changedNotices: summary.changedNotices,
    affectedWeeks: summary.affectedWeeks,
  );
}

class SchedulePendingChangesResult {
  final String? yearTerm;
  final List<ScheduleWeekChange> changes;

  const SchedulePendingChangesResult({
    required this.yearTerm,
    required this.changes,
  });

  const SchedulePendingChangesResult.empty()
    : yearTerm = null,
      changes = const <ScheduleWeekChange>[];
}

SchedulePendingChangesResult parseScheduleUpdatePendingPayload(String raw) {
  try {
    final decoded = json.decode(raw);
    if (decoded is! Map<String, dynamic>) {
      return const SchedulePendingChangesResult.empty();
    }
    final yearTerm = (decoded['yearTerm'] ?? '').toString().trim();
    final items = decoded['changes'];
    if (items is! List) {
      return SchedulePendingChangesResult(
        yearTerm: yearTerm.isEmpty ? null : yearTerm,
        changes: const <ScheduleWeekChange>[],
      );
    }

    final changes = <ScheduleWeekChange>[];
    for (final item in items) {
      if (item is! Map) continue;
      final weekNum = (item['weekNum'] ?? '').toString();
      final linesRaw = item['lines'];
      final lines = linesRaw is List
          ? linesRaw.map((e) => e.toString()).toList()
          : const <String>[];
      if (weekNum.isEmpty) continue;
      changes.add(ScheduleWeekChange(weekNum: weekNum, lines: lines));
    }
    return SchedulePendingChangesResult(
      yearTerm: yearTerm.isEmpty ? null : yearTerm,
      changes: changes,
    );
  } catch (_) {
    return const SchedulePendingChangesResult.empty();
  }
}
