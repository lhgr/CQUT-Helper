import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter_test/flutter_test.dart';

ScheduleData scheduleForWeek(int week, {int termWeekCount = 20}) {
  final monday = DateTime(2026, 8, 17).add(Duration(days: (week - 1) * 7));
  String two(int value) => value.toString().padLeft(2, '0');
  return ScheduleData(
    yearTerm: '2026-2027-1',
    weekNum: '$week',
    weekList: [for (var value = 1; value <= termWeekCount; value++) '$value'],
    weekDayList: [
      for (var day = 0; day < 7; day++)
        WeekDayItem(
          weekDay: '${day + 1}',
          weekDate: () {
            final date = monday.add(Duration(days: day));
            return '${date.year}-${two(date.month)}-${two(date.day)}';
          }(),
        ),
    ],
  );
}

void main() {
  test('没有可用的当前学期课表时不能误判为覆盖完整', () {
    final coverage = evaluateCourseReminderCoverage(
      schedules: const [],
      now: DateTime(2026, 8, 20),
      horizon: DateTime(2026, 10, 19),
    );

    expect(coverage.measurable, isFalse);
    expect(coverage.complete, isFalse);
  });

  test('按真实日期窗口计算提醒所需周次', () {
    final coverage = evaluateCourseReminderCoverage(
      schedules: [scheduleForWeek(1)],
      now: DateTime(2026, 8, 20),
      horizon: DateTime(2026, 9, 9),
    );

    expect(coverage.expectedWeeks, {'1', '2', '3', '4'});
    expect(coverage.cachedWeeks, {'1'});
    expect(coverage.complete, isFalse);
  });

  test('只有日期窗口内的每一周均缓存时才算覆盖完整', () {
    final schedules = [
      for (var week = 1; week <= 10; week++) scheduleForWeek(week),
    ];
    final complete = evaluateCourseReminderCoverage(
      schedules: schedules,
      now: DateTime(2026, 8, 20),
      horizon: DateTime(2026, 10, 19),
    );
    final incomplete = evaluateCourseReminderCoverage(
      schedules: schedules.take(9),
      now: DateTime(2026, 8, 20),
      horizon: DateTime(2026, 10, 19),
    );

    expect(complete.expectedWeekCount, 10);
    expect(complete.cachedWeekCount, 10);
    expect(complete.complete, isTrue);
    expect(incomplete.cachedWeekCount, 9);
    expect(incomplete.complete, isFalse);
  });
}
