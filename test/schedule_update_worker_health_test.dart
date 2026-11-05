import 'dart:convert';

import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
            }),
          if (testCase.mainStatus != null)
            'schedule_background_poll_daily_state': json.encode({
              'logicalDateBjt': todayBjt,
              'main': {
                'status': testCase.mainStatus,
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
