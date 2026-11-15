import 'dart:convert';

import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/schedule_update_worker_state_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final age in [
    const Duration(hours: 48),
    const Duration(hours: 48, microseconds: 1),
  ]) {
    test('真实后台成功窗口 $age', () async {
      final now = DateTime.utc(2026, 11, 15, 2);
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': now
            .subtract(const Duration(days: 5))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'status': 'sync_registered',
        }),
        'schedule_background_poll_daily_state': json.encode({
          'main': {
            'status': 'succeeded',
            'finishedAt': now.subtract(age).toIso8601String(),
          },
        }),
      });
      final health = await loadScheduleUpdateWorkerHealthSnapshot(now: now);
      expect(
        health.status,
        age == const Duration(hours: 48)
            ? ScheduleBackgroundPollHealthStatus.healthy
            : ScheduleBackgroundPollHealthStatus.restricted,
      );
    });
  }
  test('旧成功时间和前台成功不能证明后台成功', () async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'schedule_background_polling_enabled': true,
      'schedule_background_poll_enabled_at': now
          .subtract(const Duration(days: 5))
          .toIso8601String(),
      'schedule_background_poll_sync_state': json.encode({
        'status': 'sync_registered',
      }),
      'schedule_background_poll_last_success_at': now.toIso8601String(),
      'schedule_background_poll_last_state': json.encode({
        'status': 'no_changes',
        'trigger': 'foreground',
        'at': now.toIso8601String(),
      }),
    });
    final health = await loadScheduleUpdateWorkerHealthSnapshot(now: now);
    expect(health.status, ScheduleBackgroundPollHealthStatus.restricted);
    expect(health.lastSuccessAt, isNull);
  });
  for (final trigger in [
    'foreground',
    'academic_calendar_daily',
    'widget_manual',
    'daily_9am',
  ]) {
    test('近期成功后 $trigger 失败', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': now
            .subtract(const Duration(days: 5))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'status': 'sync_registered',
        }),
        'schedule_background_poll_daily_state': json.encode({
          'main': {
            'status': 'succeeded',
            'finishedAt': now
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          },
        }),
        'schedule_background_poll_last_state': json.encode({
          'status': 'pipeline_failed',
          'trigger': trigger,
          'task': 'schedule_notice_poll_task',
          'at': now.toIso8601String(),
        }),
      });
      final health = await loadScheduleUpdateWorkerHealthSnapshot(now: now);
      expect(
        health.status,
        trigger != 'daily_9am'
            ? ScheduleBackgroundPollHealthStatus.healthy
            : ScheduleBackgroundPollHealthStatus.failed,
      );
    });
  }
  for (final latestStatus in ['started', 'skip_deep_night']) {
    test('后台成功来源在 $latestStatus 覆盖后仍保留', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': now
            .subtract(const Duration(days: 5))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'status': 'sync_registered',
        }),
        'schedule_background_poll_last_success_at': now
            .subtract(const Duration(hours: 1))
            .toIso8601String(),
        'schedule_background_poll_last_success_trigger': 'immediate',
        'schedule_background_poll_last_state': json.encode({
          'status': latestStatus,
          'trigger': 'daily_9am',
          'task': 'schedule_notice_poll_task',
          'at': now.toIso8601String(),
        }),
      });
      expect(
        (await loadScheduleUpdateWorkerHealthSnapshot(now: now)).status,
        ScheduleBackgroundPollHealthStatus.healthy,
      );
    });
  }
  test('近期成功后发生注册失败仍异常', () async {
    final now = DateTime.now();
    SharedPreferences.setMockInitialValues({
      'schedule_background_polling_enabled': true,
      'schedule_background_poll_enabled_at': now.toIso8601String(),
      'schedule_background_poll_sync_state': json.encode({
        'status': 'sync_start',
        'at': now.toIso8601String(),
      }),
      'schedule_background_poll_last_success_at': now
          .subtract(const Duration(hours: 1))
          .toIso8601String(),
      'schedule_background_poll_last_success_trigger': 'immediate',
    });
    expect(
      (await loadScheduleUpdateWorkerHealthSnapshot(now: now)).status,
      ScheduleBackgroundPollHealthStatus.failed,
    );
  });
  for (final successStatus in [
    'api_closed',
    'no_changes',
    'changes_detected',
  ]) {
    test('$successStatus 同次后续注册失败不能报告健康', () async {
      final now = DateTime.now();
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': now
            .subtract(const Duration(days: 5))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'status': 'sync_registered',
        }),
        'schedule_background_poll_last_success_at': now.toIso8601String(),
        'schedule_background_poll_last_success_trigger': 'immediate',
        'schedule_background_poll_last_state': json.encode({
          'status': successStatus,
          'trigger': 'immediate',
          'task': 'schedule_notice_poll_task',
          'at': now.toIso8601String(),
          'fields': {'follow_up_outcome': 'failed'},
        }),
      });
      final snapshot = await loadScheduleUpdateWorkerHealthSnapshot(now: now);
      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.failed);
      expect(snapshot.detail, contains('后续后台任务未成功注册'));
    });
  }
  test('immediate API 关闭完成后新任务开始仍保留成功证据', () async {
    SharedPreferences.setMockInitialValues({
      'schedule_background_polling_enabled': true,
      'schedule_background_poll_enabled_at': DateTime.now()
          .subtract(const Duration(days: 5))
          .toIso8601String(),
      'schedule_background_poll_sync_state': json.encode({
        'status': 'sync_registered',
      }),
    });
    await recordScheduleUpdateWorkerSuccessfulRun(trigger: 'immediate');
    await recordScheduleUpdateWorkerState(
      status: 'api_closed',
      trigger: 'immediate',
      task: 'schedule_notice_poll_task',
    );
    expect(
      (await loadScheduleUpdateWorkerHealthSnapshot()).status,
      ScheduleBackgroundPollHealthStatus.healthy,
    );
    await recordScheduleUpdateWorkerState(
      status: 'started',
      trigger: 'daily_9am',
      task: 'schedule_notice_poll_task',
    );
    expect(
      (await loadScheduleUpdateWorkerHealthSnapshot()).status,
      ScheduleBackgroundPollHealthStatus.healthy,
    );
  });
  group('ScheduleUpdateWorker.loadHealthSnapshot', () {
    for (final testCase in [
      (
        name: '轮询关闭时返回 observing-disabled 状态',
        enabled: false,
        enabledAge: const Duration(hours: 4),
        syncStatus: 'sync_registered',
        syncAge: Duration.zero,
        lastRunStatus: null,
        lastRunAge: Duration.zero,
        mainStatus: null,
        status: ScheduleBackgroundPollHealthStatus.observing,
      ),
      (
        name: '开启后仍在观察期时返回 observing 状态',
        enabled: true,
        enabledAge: const Duration(minutes: 30),
        syncStatus: null,
        syncAge: Duration.zero,
        lastRunStatus: null,
        lastRunAge: Duration.zero,
        mainStatus: null,
        status: ScheduleBackgroundPollHealthStatus.observing,
      ),
      (
        name: '今日主任务成功时返回 healthy 状态',
        enabled: true,
        enabledAge: const Duration(hours: 4),
        syncStatus: 'sync_registered',
        syncAge: Duration.zero,
        lastRunStatus: null,
        lastRunAge: Duration.zero,
        mainStatus: 'succeeded',
        status: ScheduleBackgroundPollHealthStatus.healthy,
      ),
      (
        name: '最近夜间跳过时返回 pausedAtNight 状态',
        enabled: true,
        enabledAge: const Duration(hours: 4),
        syncStatus: 'sync_registered',
        syncAge: Duration.zero,
        lastRunStatus: 'skip_deep_night',
        lastRunAge: const Duration(minutes: 20),
        mainStatus: null,
        status: ScheduleBackgroundPollHealthStatus.pausedAtNight,
      ),
      (
        name: '今日 9 点失败且已安排 12 点补跑时返回 failed 状态',
        enabled: true,
        enabledAge: const Duration(hours: 4),
        syncStatus: 'sync_registered',
        syncAge: Duration.zero,
        lastRunStatus: null,
        lastRunAge: Duration.zero,
        mainStatus: 'failed',
        status: ScheduleBackgroundPollHealthStatus.failed,
      ),
      (
        name: '未完成注册时返回 failed 状态',
        enabled: true,
        enabledAge: const Duration(hours: 4),
        syncStatus: 'sync_start',
        syncAge: const Duration(minutes: 5),
        lastRunStatus: null,
        lastRunAge: Duration.zero,
        mainStatus: null,
        status: ScheduleBackgroundPollHealthStatus.failed,
      ),
      (
        name: '长时间无成功记录但已注册时返回 restricted 状态',
        enabled: true,
        enabledAge: const Duration(days: 4),
        syncStatus: 'sync_registered',
        syncAge: const Duration(days: 3),
        lastRunStatus: 'started',
        lastRunAge: const Duration(days: 3),
        mainStatus: null,
        status: ScheduleBackgroundPollHealthStatus.restricted,
      ),
    ]) {
      test(testCase.name, () async {
        final now = DateTime.now();
        final todayBjt = now
            .toUtc()
            .add(const Duration(hours: 8))
            .toIso8601String()
            .split('T')
            .first;
        SharedPreferences.setMockInitialValues({
          'schedule_background_polling_enabled': testCase.enabled,
          'schedule_background_poll_enabled_at': now
              .subtract(testCase.enabledAge)
              .toIso8601String(),
          if (testCase.syncStatus != null)
            'schedule_background_poll_sync_state': json.encode({
              'at': now.subtract(testCase.syncAge).toIso8601String(),
              'status': testCase.syncStatus,
            }),
          if (testCase.lastRunStatus != null)
            'schedule_background_poll_last_state': json.encode({
              'at': now.subtract(testCase.lastRunAge).toIso8601String(),
              'status': testCase.lastRunStatus,
              'trigger': 'daily_9am',
              'task': 'schedule_notice_poll_task',
            }),
          if (testCase.mainStatus != null)
            'schedule_background_poll_daily_state': json.encode({
              'logicalDateBjt': todayBjt,
              'main': {
                'status': testCase.mainStatus,
                'finishedAt': now.toIso8601String(),
                if (testCase.mainStatus == 'failed') 'retryEligible': true,
              },
              if (testCase.mainStatus == 'failed')
                'retry': {
                  'status': 'scheduled',
                  'attempted': false,
                  'scheduledFor': '${todayBjt}T12:00:00+08:00',
                },
            }),
        });
        final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();
        expect(snapshot.status, testCase.status);
      });
    }
  });
}
