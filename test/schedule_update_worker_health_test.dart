import 'dart:convert';

import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleUpdateWorker.loadHealthSnapshot', () {
    test('轮询关闭时返回 observing-disabled 状态', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': false,
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.observing);
      expect(snapshot.title, '后台定时轮询已关闭');
    });

    test('开启后仍在观察期时返回 observing 状态', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.observing);
      expect(snapshot.title, '后台定时轮询观察中');
    });

    test('今日主任务成功时返回 healthy 状态', () async {
      final todayBjt = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .split('T')
          .first;
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(hours: 4))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'at': DateTime.now().toIso8601String(),
          'status': 'sync_registered',
        }),
        'schedule_background_poll_daily_state': json.encode({
          'logicalDateBjt': todayBjt,
          'main': {'status': 'succeeded'},
        }),
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.healthy);
      expect(snapshot.title, '后台定时轮询运行正常');
    });

    test('最近夜间跳过时返回 pausedAtNight 状态', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(hours: 4))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'at': DateTime.now().toIso8601String(),
          'status': 'sync_registered',
        }),
        'schedule_background_poll_last_state': json.encode({
          'at': DateTime.now()
              .subtract(const Duration(minutes: 20))
              .toIso8601String(),
          'status': 'skip_deep_night',
        }),
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.pausedAtNight);
      expect(snapshot.title, '后台定时轮询夜间暂停');
    });

    test('今日 9 点失败且已安排 12 点补跑时返回 failed 状态', () async {
      final todayBjt = DateTime.now()
          .toUtc()
          .add(const Duration(hours: 8))
          .toIso8601String()
          .split('T')
          .first;
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(hours: 4))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'at': DateTime.now().toIso8601String(),
          'status': 'sync_registered',
        }),
        'schedule_background_poll_daily_state': json.encode({
          'logicalDateBjt': todayBjt,
          'main': {'status': 'failed', 'retryEligible': true},
          'retry': {
            'status': 'scheduled',
            'attempted': false,
            'scheduledFor': '${todayBjt}T12:00:00+08:00',
          },
        }),
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.failed);
      expect(snapshot.title, '后台定时轮询上午失败');
    });

    test('未完成注册时返回 failed 状态', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(hours: 4))
            .toIso8601String(),
        'schedule_background_poll_sync_state': json.encode({
          'at': DateTime.now()
              .subtract(const Duration(minutes: 5))
              .toIso8601String(),
          'status': 'sync_start',
        }),
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.failed);
      expect(snapshot.title, '后台定时轮询尚未完成注册');
    });

    test('长时间无成功记录但已注册时返回 restricted 状态', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(days: 4))
            .toIso8601String(),
        'schedule_background_poll_last_state': json.encode({
          'at': DateTime.now()
              .subtract(const Duration(days: 3))
              .toIso8601String(),
          'status': 'started',
        }),
        'schedule_background_poll_sync_state': json.encode({
          'at': DateTime.now()
              .subtract(const Duration(days: 3))
              .toIso8601String(),
          'status': 'sync_registered',
        }),
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.restricted);
      expect(snapshot.title, '后台定时轮询可能受系统限制');
    });
  });
}
