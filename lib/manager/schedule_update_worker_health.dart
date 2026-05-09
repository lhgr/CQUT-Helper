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
loadScheduleUpdateWorkerHealthSnapshot({required int frequencyMinutes}) async {
  final stored = await loadScheduleUpdateWorkerStoredState();
  if (!stored.enabled) {
    return const ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.observing,
      title: '后台定时轮询已关闭',
      detail: '开启后会在后台定时检查调课通知。',
    );
  }

  final lastRunAt = DateTime.tryParse(
    ((stored.lastState?['at'] ?? '') as String?)?.trim() ?? '',
  )?.toLocal();
  final lastRunStatus = ((stored.lastState?['status'] ?? '') as String?)?.trim();
  final syncStatus = ((stored.syncState?['status'] ?? '') as String?)?.trim();
  final now = DateTime.now();
  final observeWindow = const Duration(hours: 2);
  final staleWindow = Duration(minutes: frequencyMinutes * 3);

  if (stored.enabledAt == null ||
      now.difference(stored.enabledAt!) < observeWindow) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.observing,
      title: '后台定时轮询观察中',
      detail: '刚开启后台定时轮询，系统需要一段时间建立后台执行记录。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: stored.lastSuccessAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (stored.lastSuccessAt != null &&
      now.difference(stored.lastSuccessAt!) <= staleWindow) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.healthy,
      title: '后台定时轮询运行正常',
      detail: '最近已检测到后台轮询成功执行。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: stored.lastSuccessAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (lastRunStatus == 'skip_deep_night' &&
      lastRunAt != null &&
      now.difference(lastRunAt) <= staleWindow) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.pausedAtNight,
      title: '后台定时轮询夜间暂停',
      detail: '应用会在 0:00-7:00 跳过后台轮询，白天会继续自动检查。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: stored.lastSuccessAt,
      lastRunStatus: lastRunStatus,
    );
  }

  const failureStatuses = {
    'load_network_failed',
    'pipeline_failed',
    'skip_missing_credentials',
    'skip_invalid_schedule_data',
    'skip_term_mismatch',
  };
  if (lastRunStatus != null &&
      failureStatuses.contains(lastRunStatus) &&
      lastRunAt != null &&
      now.difference(lastRunAt) <= staleWindow) {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询最近失败',
      detail: '后台任务最近执行过，但本次未成功完成，可稍后重试或检查登录状态与网络。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: stored.lastSuccessAt,
      lastRunStatus: lastRunStatus,
    );
  }

  if (syncStatus != 'sync_registered') {
    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.failed,
      title: '后台定时轮询尚未完成注册',
      detail: '后台任务尚未成功注册，请重新保存设置后再观察运行状态。',
      enabledAt: stored.enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: stored.lastSuccessAt,
      lastRunStatus: lastRunStatus,
    );
  }

  return ScheduleBackgroundPollHealthSnapshot(
    status: ScheduleBackgroundPollHealthStatus.restricted,
    title: '后台定时轮询可能受系统限制',
    detail: '长时间未检测到后台执行记录，建议检查通知权限、忽略电池优化与自启动设置。',
    enabledAt: stored.enabledAt,
    lastRunAt: lastRunAt,
    lastSuccessAt: stored.lastSuccessAt,
    lastRunStatus: lastRunStatus,
  );
}
