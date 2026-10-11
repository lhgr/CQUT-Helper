import 'dart:async';

import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/utils/course_reminder_mode.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleData _schedule(List<EventItem> events) => ScheduleData(
  weekDayList: [WeekDayItem(weekDay: '1', weekDate: '2026-10-12')],
  eventList: events,
);
EventItem _event(
  String id, {
  int? minutes,
  String start = '1',
  String count = '2',
}) => EventItem(
  eventID: id,
  eventName: id,
  weekDay: '1',
  sessionStart: start,
  sessionLast: count,
  reminderMinutes: minutes,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const clocks = {
    1: (start: 480, end: 525),
    2: (start: 525, end: 570),
    3: (start: 570, end: 615),
  };
  CourseReminderPlan plan(
    List<EventItem> events, {
    bool atStart = false,
    DateTime? now,
    Map<int, ({int start, int? end})> times = clocks,
  }) => planCourseReminders(
    schedules: [_schedule(events)],
    clocks: times,
    now: now ?? DateTime.utc(2026, 10, 11),
    horizon: DateTime.utc(2026, 10, 20),
    defaultMinutes: 10,
    atStart: atStart,
  );

  test('准时继承与正数覆盖分别生成中国学校时刻', () {
    final result = plan([
      _event('inherit'),
      _event('override', minutes: 37),
    ], atStart: true);
    expect(
      result.notifications.first.notifyAt,
      DateTime.utc(2026, 10, 11, 23, 23),
    );
    expect(result.notifications.last.notifyAt, DateTime.utc(2026, 10, 12));
    expect(result.notifications.last.title, '上课时间到了');
  });
  test('取消单课通知依然保留正在进行课程模式并合并相邻课程', () {
    final result = plan([
      _event('a', minutes: 0),
      _event('b', minutes: 0, start: '3', count: '1'),
    ], now: DateTime.utc(2026, 10, 12, 0, 20));
    expect(result.notifications, isEmpty);
    expect(result.intervals, hasLength(1));
    expect(
      result.intervals.single.startMillis,
      DateTime.utc(2026, 10, 12).millisecondsSinceEpoch,
    );
    expect(
      result.intervals.single.endMillis,
      DateTime.utc(2026, 10, 12, 2, 15).millisecondsSinceEpoch,
    );
  });
  test('缺少末节结束时间只跳过模式窗口并对重复缓存去重', () {
    final result = plan(
      [_event('a'), _event('a')],
      times: {1: (start: 480, end: null)},
    );
    expect(result.notifications, hasLength(1));
    expect(result.intervals, isEmpty);
  });
  test('sessionLast表示持续节数，第3节起两节结束在第4节', () {
    final result = plan(
      [_event('a', start: '3', count: '2')],
      times: {3: (start: 600, end: 645), 4: (start: 650, end: 695)},
    );
    expect(
      result.intervals.single.endMillis,
      DateTime.utc(2026, 10, 12, 3, 35).millisecondsSinceEpoch,
    );
  });
  test('放假不提醒，调休以实际日期计划通知与模式', () {
    final result = planCourseReminders(
      schedules: [
        _schedule([_event('a')]),
      ],
      clocks: clocks,
      now: DateTime.utc(2026, 10, 11),
      horizon: DateTime.utc(2026, 10, 14),
      defaultMinutes: 10,
      atStart: true,
      calendar: AcademicCalendarSnapshot(
        schemaVersion: 1,
        yearTerm: '2026-2027-1',
        revision: '1',
        generatedAt: DateTime.utc(2026),
        complete: true,
        days: [
          AcademicCalendarDay(
            date: DateTime(2026, 10, 12),
            kind: AcademicCalendarDayKind.holiday,
            label: '假期',
          ),
          AcademicCalendarDay(
            date: DateTime(2026, 10, 13),
            kind: AcademicCalendarDayKind.teachingDay,
            label: '补课',
            scheduleDate: DateTime(2026, 10, 12),
          ),
        ],
      ),
    );
    expect(result.notifications, hasLength(1));
    expect(result.notifications.single.notifyAt, DateTime.utc(2026, 10, 13));
    expect(
      result.intervals.single.startMillis,
      DateTime.utc(2026, 10, 13).millisecondsSinceEpoch,
    );
  });
  test('校历遍历包含窗口最后一天且准时通知恰好在截止时刻仍保留', () {
    final horizon = DateTime.utc(2026, 10, 13);
    final result = planCourseReminders(
      schedules: [
        _schedule([_event('a')]),
      ],
      clocks: clocks,
      now: DateTime.utc(2026, 10, 11),
      horizon: horizon,
      defaultMinutes: 10,
      atStart: true,
      calendar: AcademicCalendarSnapshot(
        schemaVersion: 1,
        yearTerm: '2026-2027-1',
        revision: '1',
        generatedAt: DateTime.utc(2026),
        complete: true,
        days: [
          AcademicCalendarDay(
            date: DateTime(2026, 10, 12),
            kind: AcademicCalendarDayKind.holiday,
            label: '假期',
          ),
          AcademicCalendarDay(
            date: DateTime(2026, 10, 13),
            kind: AcademicCalendarDayKind.teachingDay,
            label: '补课',
            scheduleDate: DateTime(2026, 10, 12),
          ),
        ],
      ),
    );
    expect(result.notifications.single.notifyAt, horizon);
    expect(result.intervals.single.startMillis, horizon.millisecondsSinceEpoch);
  });
  test('课程之间有间隔时保持独立模式窗口', () {
    final result = plan([
      _event('a', count: '1'),
      _event('b', start: '3', count: '1'),
    ]);
    expect(result.intervals, hasLength(2));
    expect(
      result.intervals.first.endMillis,
      lessThan(result.intervals.last.startMillis),
    );
  });
  test('关闭提醒和显式取消都通过scheduler入口恢复自动模式', () async {
    SharedPreferences.setMockInitialValues({
      ScheduleSettingsManager.remindersEnabledKey: false,
    });
    const channel = MethodChannel('cqut/course_reminders');
    final calls = <String>[];
    CourseReminderMode.debugIsAndroidOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call.method);
          return null;
        });
    addTearDown(() {
      CourseReminderMode.debugIsAndroidOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      SharedPreferences.setMockInitialValues({});
    });
    await CourseReminderScheduler.rescheduleForUser('test-account');
    expect(calls, ['cancelAndRestore']);
    final status = await CourseReminderScheduler.loadStatus();
    expect(status.enabled, isFalse);
    expect(status.ready, isFalse);
    await CourseReminderScheduler.cancelAll();
    expect(calls, ['cancelAndRestore', 'cancelAndRestore']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('schedule_course_reminder_ids_v1'), isFalse);
  });
  test('排队取消串行执行，失败保留错误且不清空较新任务', () async {
    SharedPreferences.setMockInitialValues({});
    const channel = MethodChannel('cqut/course_reminders');
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final firstGate = Completer<void>();
    final secondGate = Completer<void>();
    var calls = 0;
    CourseReminderMode.debugIsAndroidOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'cancelAndRestore');
          calls++;
          if (calls == 1) {
            firstStarted.complete();
            await firstGate.future;
            throw PlatformException(code: 'cancel_failed');
          }
          if (calls == 2) {
            secondStarted.complete();
            await secondGate.future;
          }
          return null;
        });
    addTearDown(() {
      CourseReminderMode.debugIsAndroidOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      SharedPreferences.setMockInitialValues({});
    });
    final first = CourseReminderScheduler.cancelAll();
    final failed = expectLater(
      first,
      throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'cancel_failed',
        ),
      ),
    );
    await firstStarted.future;
    final second = CourseReminderScheduler.cancelAll();
    expect(calls, 1);
    firstGate.complete();
    await failed;
    await secondStarted.future;
    final third = CourseReminderScheduler.cancelAll();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 2);
    secondGate.complete();
    await Future.wait([second, third]);
    expect(calls, 3);
    await CourseReminderScheduler.cancelAll();
    expect(calls, 4);
  });
  test('channel一次传递完整模式快照并读取权限状态', () async {
    const channel = MethodChannel('cqut/course_reminders');
    final calls = <MethodCall>[];
    CourseReminderMode.debugIsAndroidOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getStatus') {
            return {
              'supported': true,
              'notificationGranted': true,
              'autoModeActive': true,
              'autoModeStatus': 'active',
            };
          }
          return null;
        });
    addTearDown(() {
      CourseReminderMode.debugIsAndroidOverride = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });
    await CourseReminderMode.replaceSchedule(
      mode: CourseAutoMode.dnd,
      intervals: const [
        CourseAutoModeInterval(startMillis: 100, endMillis: 200),
      ],
    );
    expect(calls.single.arguments, {
      'mode': 'dnd',
      'intervals': [
        {'startMillis': 100, 'endMillis': 200},
      ],
    });
    final status = await CourseReminderMode.getStatus();
    expect(
      status.supported && status.notificationGranted && status.autoModeActive,
      isTrue,
    );
    expect(status.autoModeStatus, 'active');
    await CourseReminderMode.cancelAndRestore();
    expect(calls.last.method, 'cancelAndRestore');
  });
}
