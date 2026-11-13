import 'dart:async';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_refresh_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ScheduleRefreshOrchestrator', () {
    test(
      'partial prefetch retries only failures and isolates account/term',
      () async {
        final calls = <String>[];
        var account = 'u1';
        var fail = true;
        var reminders = 0;
        final orchestrator = ScheduleRefreshOrchestrator(
          isDisposed: () => false,
          loadUserId: () async => account,
          refreshReminders: (_) async {
            reminders++;
          },
          ensureWeekLoaded:
              (
                week,
                term, {
                bool forceRefresh = false,
                bool updateLastViewed = false,
              }) async {
                calls.add('$account|$term|$week');
                return !(fail && week == '1');
              },
        );
        ScheduleData data(String term) => ScheduleData(
          weekNum: '2',
          yearTerm: term,
          weekList: const ['1', '2', '3'],
        );
        final first = await orchestrator.prefetchAllWeeksInBackground(
          data('a'),
          null,
          interval: Duration.zero,
        );
        expect(first.failedWeeks, ['1']);
        expect(calls, ['u1|a|1', 'u1|a|3']);
        // A completed pass never schedules another pass on its own.
        await Future<void>.delayed(Duration.zero);
        expect(calls.length, 2);
        fail = false;
        final retry = await orchestrator.prefetchAllWeeksInBackground(
          data('a'),
          null,
          interval: Duration.zero,
        );
        expect(retry.failedWeeks, isEmpty);
        expect(calls, ['u1|a|1', 'u1|a|3', 'u1|a|1']);
        await orchestrator.prefetchAllWeeksInBackground(
          data('a'),
          null,
          interval: Duration.zero,
        );
        expect(calls.length, 3);
        await orchestrator.prefetchAllWeeksInBackground(
          data('b'),
          null,
          interval: Duration.zero,
        );
        account = 'u2';
        await orchestrator.prefetchAllWeeksInBackground(
          data('a'),
          null,
          interval: Duration.zero,
        );
        expect(calls.skip(3), ['u1|b|1', 'u1|b|3', 'u2|a|1', 'u2|a|3']);
        expect(reminders, 4);
      },
    );

    test('failed forced refresh retries network, new weeks and cache reset are loaded', () async {
      final calls = <String>[];
      var fail = true;
      final orchestrator = ScheduleRefreshOrchestrator(
        isDisposed: () => false,
        loadUserId: () async => 'u1',
        ensureWeekLoaded:
            (
              week,
              term, {
              bool forceRefresh = false,
              bool updateLastViewed = false,
            }) async {
              calls.add('$week:$forceRefresh');
              return !fail;
            },
      );
      ScheduleData data(List<String> weeks) =>
          ScheduleData(weekNum: '2', yearTerm: 'term', weekList: weeks);
      await orchestrator.prefetchAllWeeksInBackground(
        data(['1', '2']),
        null,
        interval: Duration.zero,
        forceRefresh: true,
      );
      fail = false;
      await orchestrator.prefetchAllWeeksInBackground(
        data(['1', '2']),
        null,
        interval: Duration.zero,
      );
      expect(calls, ['1:true', '1:true']);
      await orchestrator.prefetchAllWeeksInBackground(
        data(['1', '2', '3']),
        null,
        interval: Duration.zero,
      );
      expect(calls.last, '3:false');
      orchestrator.resetPrefetchState();
      await orchestrator.prefetchAllWeeksInBackground(
        data(['1', '2', '3']),
        null,
        interval: Duration.zero,
      );
      expect(calls.skip(3), ['1:false', '3:false']);
    });

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
      firstLoad.complete(false);

      final result = await prefetch;
      expect(result.completed, isFalse);
      expect(result.failedWeeks, ['1']);
      expect(calls, ['1@2024-2025-2']);
    });

    test(
      'prefetchAllWeeksInBackground reports completed full success',
      () async {
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
                calls.add('$weekNum@$yearTerm:$forceRefresh');
                return true;
              },
          loadUserId: () async => 'u1',
        );

        final result = await orchestrator.prefetchAllWeeksInBackground(
          ScheduleData(
            weekNum: '2',
            yearTerm: '2024-2025-2',
            weekList: const ['1', '2', '3'],
          ),
          null,
          interval: Duration.zero,
          forceRefresh: true,
        );

        expect(result.completed, isTrue);
        expect(result.failedWeeks, isEmpty);
        expect(calls, ['1@2024-2025-2:true', '3@2024-2025-2:true']);
      },
    );

    test('week failure is reported while traversal still completes', () async {
      SharedPreferences.setMockInitialValues({});
      final orchestrator = ScheduleRefreshOrchestrator(
        isDisposed: () => false,
        ensureWeekLoaded: (
          weekNum,
          yearTerm, {
          bool forceRefresh = false,
          bool updateLastViewed = false,
        }) async => weekNum != '1',
        loadUserId: () async => 'u1',
      );

      final result = await orchestrator.prefetchAllWeeksInBackground(
        ScheduleData(
          weekNum: '2',
          yearTerm: '2024-2025-2',
          weekList: const ['1', '2', '3'],
        ),
        null,
        interval: Duration.zero,
      );

      expect(result.completed, isTrue);
      expect(result.failedWeeks, ['1']);
      expect(() => result.failedWeeks.add('4'), throwsUnsupportedError);
    });

    test(
      'disposed prefetch is incomplete and retains earlier week failures',
      () async {
        SharedPreferences.setMockInitialValues({});
        var disposed = false;
        final orchestrator = ScheduleRefreshOrchestrator(
          isDisposed: () => disposed,
          ensureWeekLoaded:
              (
                weekNum,
                yearTerm, {
                bool forceRefresh = false,
                bool updateLastViewed = false,
              }) async {
                disposed = true;
                return false;
              },
          loadUserId: () async => 'u1',
        );

        final result = await orchestrator.prefetchAllWeeksInBackground(
          ScheduleData(
            weekNum: '2',
            yearTerm: '2024-2025-2',
            weekList: const ['1', '2', '3'],
          ),
          null,
          interval: Duration.zero,
        );

        expect(result.completed, isFalse);
        expect(result.failedWeeks, ['1']);
      },
    );
  });
}
