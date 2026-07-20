import 'dart:convert';

import 'package:cqut_helper/manager/schedule_update_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleUpdateManager.checkPendingChanges', () {
    late ScheduleUpdateManager manager;

    setUp(() {
      manager = ScheduleUpdateManager(controller: ScheduleController());
    });

    test('account 为空时返回空结果', () async {
      SharedPreferences.setMockInitialValues({});

      final result = await manager.checkPendingChanges();

      expect(result.yearTerm, isNull);
      expect(result.changes, isEmpty);
    });

    test('pending key 缺失时返回空结果', () async {
      SharedPreferences.setMockInitialValues({'account': 'u1'});

      final result = await manager.checkPendingChanges();

      expect(result.yearTerm, isNull);
      expect(result.changes, isEmpty);
    });

    test('非法 JSON 返回空结果并移除 pending key', () async {
      final key = ScheduleUpdateWorker.pendingKeyForUser('u1');
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        key: '{bad json',
      });

      final result = await manager.checkPendingChanges();
      final prefs = await SharedPreferences.getInstance();

      expect(result.yearTerm, isNull);
      expect(result.changes, isEmpty);
      expect(prefs.getString(key), isNull);
    });

    test('payload 不是 map 时返回空结果并移除 pending key', () async {
      final key = ScheduleUpdateWorker.pendingKeyForUser('u1');
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        key: json.encode(['unexpected']),
      });

      final result = await manager.checkPendingChanges();
      final prefs = await SharedPreferences.getInstance();

      expect(result.yearTerm, isNull);
      expect(result.changes, isEmpty);
      expect(prefs.getString(key), isNull);
    });

    test('changes 不是 list 时保留 yearTerm 并返回空 changes', () async {
      final key = ScheduleUpdateWorker.pendingKeyForUser('u1');
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        key: json.encode({
          'yearTerm': '2025-2026-2',
          'changes': 'oops',
        }),
      });

      final result = await manager.checkPendingChanges();

      expect(result.yearTerm, '2025-2026-2');
      expect(result.changes, isEmpty);
    });

    test('合法 payload 能正确解析并移除 pending key', () async {
      final key = ScheduleUpdateWorker.pendingKeyForUser('u1');
      SharedPreferences.setMockInitialValues({
        'account': 'u1',
        key: json.encode({
          'yearTerm': '2025-2026-2',
          'changes': [
            {
              'weekNum': '3',
              'lines': ['新增：高等数学', 42],
            },
            {
              'weekNum': '',
              'lines': ['应被跳过'],
            },
            'bad item',
          ],
        }),
      });

      final result = await manager.checkPendingChanges();
      final prefs = await SharedPreferences.getInstance();

      expect(result.yearTerm, '2025-2026-2');
      expect(result.changes, hasLength(1));
      expect(result.changes.single.weekNum, '3');
      expect(result.changes.single.lines, ['新增：高等数学', '42']);
      expect(prefs.getString(key), isNull);
    });
  });
}
