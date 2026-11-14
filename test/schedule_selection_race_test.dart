import 'dart:async';
import 'dart:convert';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/pages/ClassSchedule/ClassSchedule.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_refresh_orchestrator.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_app_bar.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleData _week(String number, {String term = 'term'}) {
  final today = DateTime.now();
  final monday = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: today.weekday - 1));
  return ScheduleData(
    weekNum: number,
    yearTerm: term,
    weekList: ['1', '2', '3'],
    eventList: [],
    weekDayList: List.generate(7, (index) {
      final date = monday.add(Duration(days: index));
      return WeekDayItem(
        weekDate:
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
        weekDay: '${index + 1}',
      );
    }),
  );
}

class _Controller extends ScheduleController {
  final requests = <Completer<ScheduleData>>[];
  final weeks = <String, Completer<bool>>{};
  final destinations = <String, Completer<ScheduleData>>{};
  final remembered = <ScheduleData>[];
  @override
  Future<ScheduleData> loadWeekForNavigation(String week, String term) {
    final request = Completer<ScheduleData>();
    destinations['$term/$week'] = request;
    return request.future;
  }

  @override
  String? get userId => 'u1';
  @override
  Future<void> loadCredentials() async {}
  @override
  Future<bool> loadTimeInfoFromCacheIfAny() async => false;
  @override
  Future<bool> refreshTimeInfoIfEnabled({bool force = false}) async => false;
  @override
  Future<bool> isFresh(
    ScheduleData data, {
    Duration maxAge = const Duration(minutes: 15),
  }) async => true;
  @override
  Future<ScheduleData?> loadFromCache({
    String? weekNum,
    String? yearTerm,
  }) async => _week(weekNum ?? '1');
  @override
  Future<ScheduleData> loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
    String trigger = 'schedule_load',
    bool waitForSideEffects = true,
    bool refreshReminders = true,
  }) {
    selectWeek(weekNum, yearTerm);
    final request = Completer<ScheduleData>();
    requests.add(request);
    return request.future;
  }

  @override
  Future<void> rememberSelection(ScheduleData data) async {
    remembered.add(data);
  }

  @override
  void schedulePrefetch(
    ScheduleData data,
    Function() onUpdate, {
    Duration delay = const Duration(milliseconds: 300),
  }) {}
  @override
  Future<SchedulePrefetchResult> prefetchAllWeeksInBackground(
    ScheduleData data,
    void Function()? onUpdate, {
    Duration interval = const Duration(milliseconds: 150),
    bool forceRefresh = false,
    bool refreshReminders = true,
  }) async => SchedulePrefetchResult(completed: true);
  @override
  Future<bool> ensureWeekLoaded(
    String week,
    String term, {
    bool forceRefresh = false,
    bool updateLastViewed = false,
    bool rethrowOnFailure = false,
    bool refreshReminders = true,
  }) async {
    final pending = weeks[week]?.isCompleted == false
        ? weeks[week]!
        : (weeks[week] = Completer<bool>());
    final loaded = await pending.future;
    if (loaded) processLoadedData(_week(week));
    return loaded;
  }
}

void main() {
  setUp(() => ScheduleUpdateIntents.openWeek.value = null);
  tearDown(() => ScheduleUpdateIntents.openWeek.value = null);
  Future<void> open(WidgetTester tester, _Controller controller) async {
    SharedPreferences.setMockInitialValues({
      'account': 'u1',
      'time_info_enabled': false,
      'academic_calendar_checked_at_v1_term':
          DateTime.now().millisecondsSinceEpoch,
      'academic_calendar_snapshot_v1_term': jsonEncode({
        'schema_version': 1,
        'year_term': 'term',
        'revision': 'test',
        'generated_at': DateTime.now().toIso8601String(),
        'term_calendar_complete': true,
        'days': [],
      }),
    });
    await tester.pumpWidget(
      MaterialApp(home: ClassscheduleView(controller: controller)),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(ScheduleAppBar), findsOneWidget);
  }

  ScheduleAppBar bar(WidgetTester tester) =>
      tester.widget<ScheduleAppBar>(find.byType(ScheduleAppBar));
  SchedulePageView pages(WidgetTester tester) =>
      tester.widget<SchedulePageView>(find.byType(SchedulePageView));

  Future<void> locate(
    WidgetTester tester,
    String week, {
    String term = 'old-term',
  }) async {
    ScheduleUpdateIntents.requestOpenWeek(
      userId: 'u1',
      yearTerm: term,
      weekNum: week,
    );
    for (var frame = 0; frame < 8; frame++) {
      await tester.pump();
    }
  }

  testWidgets(
    'historical destination failure preserves visible term cache and selection then retries',
    (tester) async {
      final controller = _Controller();
      await open(tester, controller);
      await locate(tester, '2');
      expect(controller.currentTerm, 'term');
      expect(controller.weekCache[1]?.yearTerm, 'term');
      expect(controller.remembered, isEmpty);
      controller.destinations['old-term/2']!.completeError(
        StateError('offline'),
      );
      await tester.pump();
      expect(bar(tester).currentScheduleData!.yearTerm, 'term');
      expect(controller.currentTerm, 'term');
      expect(controller.weekCache[1]?.yearTerm, 'term');
      expect(controller.remembered, isEmpty);
      expect(find.text('无法打开old-term学期第2周课表。'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pump();
      controller.destinations['old-term/2']!.complete(
        _week('2', term: 'old-term'),
      );
      await tester.pump();
      await tester.pump();
      expect(bar(tester).currentScheduleData!.yearTerm, 'old-term');
      expect(bar(tester).currentWeekIndex, 1);
      expect(controller.remembered.last.weekNum, '2');
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'mismatched historical week is rejected before changing current cache',
    (tester) async {
      final controller = _Controller();
      await open(tester, controller);
      await locate(tester, '2');
      controller.destinations['old-term/2']!.complete(
        _week('3', term: 'old-term'),
      );
      await tester.pump();
      expect(controller.currentTerm, 'term');
      expect(controller.weekCache.keys, [1]);
      expect(controller.remembered, isEmpty);
      expect(find.text('无法打开old-term学期第2周课表。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'new destination and manual week selection supersede old responses',
    (tester) async {
      final controller = _Controller();
      await open(tester, controller);
      await locate(tester, '2');
      await locate(tester, '3');
      controller.destinations['old-term/2']!.complete(
        _week('2', term: 'old-term'),
      );
      await tester.pump();
      expect(controller.currentTerm, 'term');
      pages(tester).onPageChanged(1);
      await tester.pump();
      controller.weeks['2']!.complete(true);
      await tester.pump();
      controller.destinations['old-term/3']!.complete(
        _week('3', term: 'old-term'),
      );
      await tester.pump();
      expect(controller.currentTerm, 'term');
      expect(bar(tester).currentScheduleData!.weekNum, '2');
      expect(find.textContaining('无法打开'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'pending destination survives lazy initialization and account changes discard response',
    (tester) async {
      final controller = _Controller();
      ScheduleUpdateIntents.requestOpenWeek(
        userId: 'u1',
        yearTerm: 'old-term',
        weekNum: '2',
      );
      await open(tester, controller);
      for (var frame = 0; frame < 8; frame++) {
        await tester.pump();
      }
      expect(controller.destinations, contains('old-term/2'));
      expect(ScheduleUpdateIntents.openWeek.value, isNull);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('account', 'u2');
      controller.destinations['old-term/2']!.complete(
        _week('2', term: 'old-term'),
      );
      await tester.pump();
      expect(controller.currentTerm, 'term');
      expect(controller.remembered, isEmpty);
      expect(find.textContaining('无法打开'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('same-term memory destination requires no navigation fetch', (
    tester,
  ) async {
    final controller = _Controller();
    await open(tester, controller);
    controller.weekCache[2] = _week('2');
    await locate(tester, '2', term: 'term');
    expect(controller.destinations, isEmpty);
    expect(bar(tester).currentWeekIndex, 1);
    expect(controller.remembered.last.weekNum, '2');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('failed week retries only that week and clears after success', (
    tester,
  ) async {
    final controller = _Controller();
    await open(tester, controller);
    pages(tester).onPageChanged(1);
    await tester.pump();
    controller.weeks['2']!.complete(false);
    await tester.pump();
    expect(pages(tester).failedWeeks, {2});
    expect(find.byType(SnackBar), findsNothing);
    pages(tester).onRetryWeek!('2');
    await tester.pump();
    expect(pages(tester).failedWeeks, isEmpty);
    expect(controller.weeks.keys, ['2']);
    expect(controller.requests, isEmpty);
    controller.weeks['2']!.complete(true);
    await tester.pump();
    expect(pages(tester).failedWeeks, isEmpty);
    expect(bar(tester).currentScheduleData!.weekNum, '2');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late failed week cannot mark the newer selected week failed', (
    tester,
  ) async {
    final controller = _Controller();
    await open(tester, controller);
    pages(tester).onPageChanged(1);
    await tester.pump();
    pages(tester).onPageChanged(2);
    await tester.pump();
    controller.weeks['2']!.complete(false);
    await tester.pump();
    expect(pages(tester).failedWeeks, isEmpty);
    controller.weeks['3']!.complete(true);
    await tester.pump();
    expect(bar(tester).currentScheduleData!.weekNum, '3');
    expect(pages(tester).failedWeeks, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('thrown cache load failure becomes a recoverable week error', (
    tester,
  ) async {
    final controller = _Controller();
    await open(tester, controller);
    pages(tester).onPageChanged(1);
    await tester.pump();
    controller.weeks['2']!.completeError(StateError('cache unavailable'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(pages(tester).failedWeeks, {2});
    expect(pages(tester).onRetryWeek, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('term replacement clears failures and ignores old week failure', (
    tester,
  ) async {
    final controller = _Controller();
    await open(tester, controller);
    pages(tester).onPageChanged(1);
    await tester.pump();
    controller.weeks['2']!.complete(false);
    await tester.pump();
    expect(pages(tester).failedWeeks, {2});
    pages(tester).onPageChanged(2);
    await tester.pump();
    bar(tester).onRefresh();
    await tester.pump();
    controller.requests.single.complete(_week('1', term: 'next-term'));
    await tester.pump();
    await tester.pump();
    expect(bar(tester).currentScheduleData!.yearTerm, 'next-term');
    expect(pages(tester).failedWeeks, isEmpty);
    controller.weeks['3']!.complete(false);
    await tester.pump();
    expect(pages(tester).failedWeeks, isEmpty);
    expect(bar(tester).currentScheduleData!.yearTerm, 'next-term');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('late week response leaves newer selected week visible', (
    tester,
  ) async {
    final controller = _Controller();
    await open(tester, controller);
    pages(tester).onPageChanged(1);
    await tester.pump();
    pages(tester).onPageChanged(2);
    await tester.pump();
    controller.weeks['3']!.complete(true);
    await tester.pump();
    expect(bar(tester).currentScheduleData!.weekNum, '3');
    controller.weeks['2']!.complete(true);
    await tester.pump();
    expect(bar(tester).currentScheduleData!.weekNum, '3');
    expect(bar(tester).currentWeekIndex, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'old refresh failure cannot clear newer loading or replace selected data',
    (tester) async {
      final controller = _Controller();
      await open(tester, controller);
      bar(tester).onRefresh();
      await tester.pump();
      pages(tester).onPageChanged(1);
      await tester.pump();
      controller.weeks['2']!.complete(true);
      await tester.pump();
      bar(tester).onRefresh();
      await tester.pump();
      expect(controller.requests.length, 2);
      controller.requests.first.completeError(StateError('old refresh failed'));
      await tester.pump();
      expect(bar(tester).loading, isTrue);
      expect(bar(tester).currentScheduleData!.weekNum, '2');
      controller.requests.last.complete(_week('2'));
      await tester.pump();
      await tester.pump();
      expect(bar(tester).loading, isFalse);
      expect(bar(tester).currentScheduleData!.weekNum, '2');
      expect(find.text('无法加载课表，请检查网络后重试。'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
