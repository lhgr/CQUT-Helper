import 'dart:async';
import 'dart:convert';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/ClassSchedule.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_refresh_orchestrator.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_app_bar.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleData _week(String number) {
  final today = DateTime.now();
  final monday = DateTime(
    today.year,
    today.month,
    today.day,
  ).subtract(Duration(days: today.weekday - 1));
  return ScheduleData(
    weekNum: number,
    yearTerm: 'term',
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
  Future<void> rememberSelection(ScheduleData data) async {}
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
    final pending = weeks.putIfAbsent(week, Completer<bool>.new);
    final loaded = await pending.future;
    if (loaded) processLoadedData(_week(week));
    return loaded;
  }
}

void main() {
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
