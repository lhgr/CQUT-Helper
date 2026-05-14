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

    test('最近成功执行时返回 healthy 状态', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(hours: 4))
            .toIso8601String(),
        'schedule_background_poll_last_success_at': DateTime.now()
            .subtract(const Duration(minutes: 20))
            .toIso8601String(),
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

    test('最近失败状态时返回 failed 状态', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_background_polling_enabled': true,
        'schedule_background_poll_enabled_at': DateTime.now()
            .subtract(const Duration(hours: 4))
            .toIso8601String(),
        'schedule_background_poll_last_state': json.encode({
          'at': DateTime.now()
              .subtract(const Duration(minutes: 10))
              .toIso8601String(),
          'status': 'load_network_failed',
        }),
      });

      final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();

      expect(snapshot.status, ScheduleBackgroundPollHealthStatus.failed);
      expect(snapshot.title, '后台定时轮询最近失败');
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
            .subtract(const Duration(hours: 6))
            .toIso8601String(),
        'schedule_background_poll_last_state': json.encode({
          'at': DateTime.now()
              .subtract(const Duration(hours: 4))
              .toIso8601String(),
          'status': 'started',
        }),
        'schedule_background_poll_sync_state': json.encode({
          'at': DateTime.now()
              .subtract(const Duration(hours: 4))
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
