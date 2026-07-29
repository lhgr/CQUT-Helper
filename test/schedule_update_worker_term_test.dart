import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleUpdateWorker.resolvePollingTarget', () {
    test('优先使用当前学期锚点(widget)而非当前查看学期', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_widget_term_u1': '2025-2026-2',
        'schedule_widget_week_u1': '8',
        'schedule_last_term_u1': '2024-2025-2',
        'schedule_last_week_u1': '6',
      });
      final prefs = await SharedPreferences.getInstance();
      final target = ScheduleUpdateWorker.resolvePollingTarget(
        prefs: prefs,
        userId: 'u1',
      );

      expect(target.yearTerm, '2025-2026-2');
      expect(target.weekNum, '8');
    });

    test('当前学期锚点缺失时回退到当前查看学期，非法周次回退到1', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_last_term_u1': '2023-2024-1',
        'schedule_last_week_u1': 'abc',
      });
      final prefs = await SharedPreferences.getInstance();
      final target = ScheduleUpdateWorker.resolvePollingTarget(
        prefs: prefs,
        userId: 'u1',
      );

      expect(target.yearTerm, '2023-2024-1');
      expect(target.weekNum, '1');
    });
  });

  group('ScheduleUpdateWorker 后台任务参数', () {
    test('只保存账号和调度元数据，不复制教务系统凭证', () {
      final inputData = ScheduleUpdateWorker.buildTaskInputData(
        userId: 'u1',
        trigger: 'daily_9am',
        logicalDateBjt: '2026-07-29',
        scheduledAtBjt: '2026-07-29T09:00:00+08:00',
      );

      expect(inputData['userId'], 'u1');
      expect(inputData['trigger'], 'daily_9am');
      expect(inputData.containsKey('encryptedPassword'), isFalse);
      expect(inputData.values, isNot(contains('secure-p1')));
    });
  });
}
