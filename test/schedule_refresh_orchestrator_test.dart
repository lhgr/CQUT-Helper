import 'dart:async';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_refresh_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleRefreshOrchestrator', () {
    test('schedulePrefetch 只预取相邻周', () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      final orchestrator = ScheduleRefreshOrchestrator(
        isDisposed: () => false,
        ensureWeekLoaded:
            (
              weekNum,
              yearTerm, {
              bool forceRefresh = false,
              bool updateLastViewed = false,
            }) async {
              calls.add('$weekNum@$yearTerm');
              return true;
            },
        loadUserId: () async => 'u1',
      );

      orchestrator.schedulePrefetch(
        ScheduleData(
          weekNum: '2',
          yearTerm: '2024-2025-2',
          weekList: const ['1', '2', '3', '4'],
        ),
        () {},
        delay: Duration.zero,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(calls, ['1@2024-2025-2', '3@2024-2025-2']);
    });

    test('refreshAllWeeksInForeground 命中 cooldown 时不重复刷新', () async {
      SharedPreferences.setMockInitialValues({
        'schedule_foreground_full_refresh_at_u1_2024-2025-2':
            DateTime.now().millisecondsSinceEpoch,
      });
      final calls = <String>[];
      final orchestrator = ScheduleRefreshOrchestrator(
        isDisposed: () => false,
        ensureWeekLoaded:
            (
              weekNum,
              yearTerm, {
              bool forceRefresh = false,
              bool updateLastViewed = false,
            }) async {
              calls.add('$weekNum@$yearTerm:$forceRefresh:$updateLastViewed');
              return true;
            },
        loadUserId: () async => 'u1',
      );

      await orchestrator.refreshAllWeeksInForeground(
        ScheduleData(
          weekNum: '2',
          yearTerm: '2024-2025-2',
          weekList: const ['1', '2', '3'],
        ),
        interval: Duration.zero,
      );

      expect(calls, isEmpty);
    });

    test('cancelPrefetch 会在当前周加载完成后终止剩余全周预取', () async {
      SharedPreferences.setMockInitialValues({});
      final calls = <String>[];
      final firstLoad = Completer<bool>();
      final orchestrator = ScheduleRefreshOrchestrator(
        isDisposed: () => false,
        ensureWeekLoaded:
            (
              weekNum,
              yearTerm, {
              bool forceRefresh = false,
              bool updateLastViewed = false,
            }) {
              calls.add('$weekNum@$yearTerm');
              return calls.length == 1 ? firstLoad.future : Future.value(true);
            },
        loadUserId: () async => 'u1',
      );

      final prefetch = orchestrator.prefetchAllWeeksInBackground(
        ScheduleData(
          weekNum: '2',
          yearTerm: '2024-2025-2',
          weekList: const ['1', '2', '3', '4'],
        ),
        null,
        interval: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);
      orchestrator.cancelPrefetch();
      firstLoad.complete(true);

      expect(await prefetch, isFalse);
      expect(calls, ['1@2024-2025-2']);
    });
  });
}
