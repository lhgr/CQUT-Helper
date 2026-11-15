import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/utils/exam_schedule_projection.dart';
import 'package:flutter_test/flutter_test.dart';

List<CampusTimeInfo> times() => [
  for (var i = 0; i < 10; i++)
    CampusTimeInfo(
      sessionNum: i + 1,
      startTime: '${8 + i + (i >= 4 ? 2 : 0)}:00',
      endTime: '${8 + i + (i >= 4 ? 2 : 0)}:45',
    ),
];

ExamRecord exam(String key, String start, String end) => ExamRecord(
  key: key,
  courseName: '数学考试',
  timeText: '$start-$end',
  campus: '',
  building: '',
  room: '',
  startAt: DateTime.parse(start),
  endAt: DateTime.parse(end),
);

void main() {
  test('class times map linearly, all breaks collapse to boundaries', () {
    final axis = ExamTimeAxis.tryCreate(times(), sessionHeight: 60)!;
    expect(axis.position(8 * 60), 0);
    expect(axis.position(8 * 60 + 15), 20);
    expect(axis.position(8 * 60 + 50), 60);
    expect(axis.position(12 * 60 + 30), 240);
    expect(axis.position(14 * 60), 240);
    expect(axis.position(6 * 60), 0);
    expect(axis.position(23 * 60), 600);
  });

  test('minimum visual bounds expand at lunch and clamp at edges', () {
    final axis = ExamTimeAxis.tryCreate(times(), sessionHeight: 60)!;
    final lunch = axis.project(
      exam('lunch', '2026-11-16T12:00:00+08:00', '2026-11-16T13:00:00+08:00'),
      1,
    );
    expect((lunch.top, lunch.height), (224, 32));
    final early = axis.project(
      exam('early', '2026-11-16T05:00:00+08:00', '2026-11-16T06:00:00+08:00'),
      1,
    );
    expect((early.top, early.height), (0, 32));
    final late = axis.project(
      exam('late', '2026-11-16T22:00:00+08:00', '2026-11-16T23:00:00+08:00'),
      1,
    );
    expect((late.top, late.height), (568, 32));
  });

  test(
    'missing, duplicate, reversed and overlapping sessions disable projection',
    () {
      expect(
        ExamTimeAxis.tryCreate(times()..removeLast(), sessionHeight: 60),
        isNull,
      );
      expect(
        ExamTimeAxis.tryCreate([...times(), times().first], sessionHeight: 60),
        isNull,
      );
      final reversed = times()..first.endTime = '07:00';
      expect(ExamTimeAxis.tryCreate(reversed, sessionHeight: 60), isNull);
      final overlap = times()..[1].startTime = '08:30';
      expect(ExamTimeAxis.tryCreate(overlap, sessionHeight: 60), isNull);
    },
  );

  test('true school date selects weekend and requires a year anchor', () {
    final sunday = exam(
      'sunday',
      '2026-11-22T09:00:00+08:00',
      '2026-11-22T11:00:00+08:00',
    );
    final next = exam(
      'next',
      '2026-11-23T09:00:00+08:00',
      '2026-11-23T11:00:00+08:00',
    );
    final data = ScheduleData(
      weekDayList: [WeekDayItem(weekDate: '2026-11-16')],
    );
    expect(examsInScheduleWeek(data, [sunday, next]), [sunday]);
    expect(
      examsInScheduleWeek(
        ScheduleData(weekDayList: [WeekDayItem(weekDate: '11-16')]),
        [sunday],
      ),
      isEmpty,
    );
  });

  test('month-day dates resolve in the selected academic term', () {
    final sunday = exam(
      'sunday',
      '2026-11-22T09:00:00+08:00',
      '2026-11-22T11:00:00+08:00',
    );
    final data = ScheduleData(
      yearTerm: '2026-2027-1',
      weekDayList: [
        WeekDayItem(weekDate: '11-16'),
        WeekDayItem(weekDate: '11/22'),
      ],
    );
    expect(scheduleExamWeekStart(data), DateTime.utc(2026, 11, 16));
    expect(examsInScheduleWeek(data, [sunday]), [sunday]);
    data.yearTerm = '2025-2026-1';
    data.weekDayList = [
      WeekDayItem(weekDate: '11-17'),
      WeekDayItem(weekDate: '11-23'),
    ];
    expect(scheduleExamWeekStart(data), DateTime.utc(2025, 11, 17));
    expect(examsInScheduleWeek(data, [sunday]), isEmpty);
  });

  test(
    'cross-year and spring weeks use term years rather than current year',
    () {
      expect(
        scheduleExamWeekStart(
          ScheduleData(
            yearTerm: '2025-2026-1',
            weekDayList: [
              WeekDayItem(weekDate: '12-29'),
              WeekDayItem(weekDate: '01-04'),
            ],
          ),
        ),
        DateTime.utc(2025, 12, 29),
      );
      expect(
        scheduleExamWeekStart(
          ScheduleData(
            yearTerm: '2024-2025-2',
            weekDayList: [WeekDayItem(weekDate: '05-19')],
          ),
        ),
        DateTime.utc(2025, 5, 19),
      );
      expect(
        scheduleExamWeekStart(
          ScheduleData(
            yearTerm: '2023-2024-1',
            weekDayList: [WeekDayItem(weekDate: '02-29')],
          ),
        ),
        DateTime.utc(2024, 2, 26),
      );
    },
  );

  test('explicit dates anchor yearless dates and inconsistent weeks fail', () {
    final data = ScheduleData(
      weekDayList: [
        WeekDayItem(weekDate: '12-29'),
        WeekDayItem(weekDate: '2026-01-04'),
      ],
    );
    expect(scheduleExamWeekStart(data), DateTime.utc(2025, 12, 29));
    data.weekDayList!.last.weekDate = '2026-01-12';
    expect(scheduleExamWeekStart(data), isNull);
    expect(
      scheduleExamWeekStart(
        ScheduleData(
          yearTerm: '2025-2027-1',
          weekDayList: [WeekDayItem(weekDate: '11-16')],
        ),
      ),
      isNull,
    );
  });

  test(
    'final exam rectangles and entire course conflict group share lanes',
    () {
      final lanes = assignScheduleLanes([
        const ScheduleLaneItem('course-group', 1, 0, 240),
        const ScheduleLaneItem('exam-a', 1, 224, 256),
        const ScheduleLaneItem('exam-b', 1, 225, 257),
        const ScheduleLaneItem('after', 1, 257, 300),
        const ScheduleLaneItem('other-day', 2, 225, 257),
      ]);
      expect(lanes['course-group'], (index: 0, count: 3));
      expect(lanes['exam-a'], (index: 1, count: 3));
      expect(lanes['exam-b'], (index: 2, count: 3));
      expect(lanes['after'], (index: 0, count: 1));
      expect(lanes['other-day'], (index: 0, count: 1));
    },
  );
}
