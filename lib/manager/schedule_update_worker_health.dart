import 'package:cqut_helper/manager/schedule_update_worker_state_store.dart';

enum ScheduleBackgroundPollHealthStatus {
  observing,
  healthy,
  failed,
  pausedAtNight,
  restricted,
}

class ScheduleBackgroundPollHealthSnapshot {
  final ScheduleBackgroundPollHealthStatus status;
  final String title;
  final String detail;
  final DateTime? enabledAt;
  final DateTime? lastRunAt;
  final DateTime? lastSuccessAt;
  final String? lastRunStatus;

  const ScheduleBackgroundPollHealthSnapshot({
    required this.status,
    required this.title,
    required this.detail,
    this.enabledAt,
    this.lastRunAt,
    this.lastSuccessAt,
    this.lastRunStatus,
  });
}

Future<ScheduleBackgroundPollHealthSnapshot>
loadScheduleUpdateWorkerHealthSnapshot({DateTime? now}) async {
  final stored = await loadScheduleUpdateWorkerStoredState();
  if (!stored.enabled) {
    return const ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.observing,
      title: '后台定时轮询已关闭',
      detail: '开启后会在后台定时检查调课通知。',
    );
  }

  final lastTrigger = stored.lastState?['trigger'];
  final isBackgroundRun =
      isScheduleUpdateWorkerBackgroundTrigger(lastTrigger) &&
      stored.lastState?['task'] == 'schedule_notice_poll_task';
  final lastRunAt = !isBackgroundRun
      ? null
      : DateTime.tryParse(
          ((stored.lastState?['at'] ?? '') as String?)?.trim() ?? '',
        )?.toLocal();
  final lastRunStatus = !isBackgroundRun
      ? null
      : ((stored.lastState?['status'] ?? '') as String?)?.trim();
  final syncStatus = ((stored.syncState?['status'] ?? '') as String?)?.trim();
  final dailyState = stored.dailyState;
  now ??= DateTime.now();
  final nowBjt = now.toUtc().add(const Duration(hours: 8));
  final today = nowBjt.toIso8601String().split('T').first;
  final observeWindow = const Duration(hours: 2);

  final successfulTimes = <DateTime>[
    if (isScheduleUpdateWorkerBackgroundTrigger(stored.lastSuccessTrigger) &&
        stored.lastSuccessAt != null)
      stored.lastSuccessAt!,
  ];
  final failedTimes = <DateTime>[];
  for (final key in ['main', 'retry']) {
    final entry = stored.dailyState?[key] as Map?;
    if (const {'failed', 'finished'}.contains(entry?['status'])) {
      final at = DateTime.tryParse((entry?['finishedAt'] ?? '').toString());
      if (at != null) failedTimes.add(at);
    }
    if (entry?['status'] == 'succeeded') {
      final at = DateTime.tryParse((entry?['finishedAt'] ?? '').toString());
      if (at != null) successfulTimes.add(at);
    }
  }
  if (isBackgroundRun &&
      const {
        'no_changes',
        'changes_detected',
        'api_closed',
      }.contains(lastRunStatus) &&
      lastRunAt != null) {
    successfulTimes.add(lastRunAt);
  }
  successfulTimes.sort();
  final successAt = successfulTimes.isEmpty ? null : successfulTimes.last;
  final successAge = successAt == null ? null : now.difference(successAt);
  final recentSuccess =
      successAge != null &&
      !successAge.isNegative &&
      successAge <= const Duration(days: 2);
  final syncAt = DateTime.tryParse((stored.syncState?['at'] ?? '').toString());
  final registrationFailed =
      syncStatus != 'sync_registered' &&
      (!recentSuccess || syncAt == null || syncAt.isAfter(successAt!));
  const failedStatuses = {
    'load_network_failed',
    'pipeline_failed',
    'skip_missing_credentials',
    'skip_invalid_schedule_data',
    'skip_term_mismatch',
    'unhandled_failed',
  };
  final newerFailure =
      (lastRunAt != null &&
          failedStatuses.contains(lastRunStatus) &&
          (successAt == null || lastRunAt.isAfter(successAt))) ||
      failedTimes.any((at) => successAt == null || at.isAfter(successAt));
  final followUpFailed =
      isBackgroundRun &&
      (stored.lastState?['fields'] as Map?)?['follow_up_outcome'] == 'failed' &&
      lastRunAt != null &&
      (successAt == null || !lastRunAt.isBefore(successAt));
  if (followUpFailed) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询后续任务注册失败',
      detail: '本次检查已完成，但后续后台任务未成功注册，请重新保存设置后再观察运行状态。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }
  if (recentSuccess && !registrationFailed && !newerFailure) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.healthy,
      title: '后台定时轮询运行正常',
      detail: '最近已成功执行后台轮询，后续会继续按北京时间 9:00 自动检查。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (recentSuccess && newerFailure) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询最近失败',
      detail: '最近一次后台轮询未成功完成，可稍后重试或检查登录状态与网络。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (!recentSuccess &&
      (stored.enabledAt == null ||
          now.difference(stored.enabledAt!) < observeWindow)) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.observing,
      title: '后台定时轮询观察中',
      detail: '刚开启后台定时轮询，系统需要一段时间建立后台执行记录。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (registrationFailed) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询尚未完成注册',
      detail: '后台任务尚未成功注册，请重新保存设置后再观察运行状态。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (lastRunStatus == 'skip_deep_night' &&
      lastRunAt != null &&
      now.difference(lastRunAt) <= const Duration(hours: 8)) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.pausedAtNight,
      title: '后台定时轮询夜间暂停',
      detail: '应用会在 0:00-7:00 跳过后台轮询，白天会继续自动检查。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  final logicalDate = ((dailyState?['logicalDateBjt'] ?? '') as String?)
      ?.trim();
  final main = (dailyState?['main'] as Map?)?.cast<String, dynamic>();
  final retry = (dailyState?['retry'] as Map?)?.cast<String, dynamic>();
  final mainStatus = ((main?['status'] ?? '') as String?)?.trim();
  final retryStatus = ((retry?['status'] ?? '') as String?)?.trim();
  final retryAttempted = retry?['attempted'] == true;

  if (logicalDate == today &&
      mainStatus == 'failed' &&
      retryStatus == 'scheduled' &&
      !retryAttempted) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询上午失败',
      detail: '今天上午轮询未成功完成，系统会在北京时间 12:00 再补跑一次。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (logicalDate == today && retryAttempted && retryStatus == 'finished') {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询今日已失败',
      detail: '今天的 9:00 主任务和 12:00 补跑都未成功完成，明天会恢复到北京时间 9:00 再次执行。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (lastRunStatus != null &&
      failedStatuses.contains(lastRunStatus) &&
      lastRunAt != null &&
      now.difference(lastRunAt) <= const Duration(hours: 24)) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询最近失败',
      detail: '后台任务最近执行过，但本次未成功完成，可稍后重试或检查登录状态与网络。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: successAt,
      lastRunStatus: lastRunStatus,
    );
  }

  return ScheduleBackgroundPollHealthSnapshot(
    status: ScheduleBackgroundPollHealthStatus.restricted,
    title: '后台定时轮询可能受系统限制',
    detail: '长时间未检测到应有的后台执行记录，建议检查通知权限、忽略电池优化与自启动设置。',
    enabledAt: stored.enabledAt,
    lastRunAt: lastRunAt,
    lastSuccessAt: successAt,
    lastRunStatus: lastRunStatus,
  );
}
