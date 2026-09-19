import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/academic_calendar_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'holiday remains empty by default and teaching day maps without recursion',
    () {
      final source = _schedule('5', [
        EventItem(eventName: '周二课程', weekDay: '2', sessionStart: '1'),
      ]);
      final calendar = AcademicCalendarSnapshot(
        schemaVersion: 1,
        yearTerm: '2026-2027-1',
        revision: 'r1',
        generatedAt: DateTime(2026, 9, 19),
        complete: true,
        days: [
          AcademicCalendarDay(
            date: DateTime(2026, 9, 29),
            kind: AcademicCalendarDayKind.holiday,
            label: '国庆节',
          ),
          AcademicCalendarDay(
            date: DateTime(2026, 9, 26),
            kind: AcademicCalendarDayKind.teachingDay,
            scheduleDate: DateTime(2026, 9, 29),
            label: '调休补课',
          ),
        ],
      );

      final holiday = resolveAcademicCalendarDay(
        actualDate: DateTime(2026, 9, 29),
        schedules: [source],
        calendar: calendar,
      );
      expect(holiday.isHoliday, isTrue);
      expect(holiday.events, isEmpty);

      final makeup = resolveAcademicCalendarDay(
        actualDate: DateTime(2026, 9, 26),
        schedules: [source],
        calendar: calendar,
      );
      expect(makeup.isTeachingDay, isTrue);
      expect(makeup.events, hasLength(1));
      expect(makeup.events.single.sourceDate, DateTime(2026, 9, 29));
      expect(makeup.events.single.actualWeekday, 6);
      expect(makeup.events.single.sourceWeekday, 2);
      expect(
        identical(makeup.events.single.event, source.eventList!.single),
        isTrue,
      );
    },
  );

  test('holiday display opt-in keeps the actual-day source events', () {
    final event = EventItem(eventName: '周二课程', weekDay: '2', sessionStart: '1');
    final holiday = resolveAcademicCalendarDay(
      actualDate: DateTime(2026, 9, 29),
      schedules: [
        _schedule('5', [event]),
      ],
      calendar: _calendar(),
      includeHolidayEvents: true,
    );

    expect(holiday.isHoliday, isTrue);
    expect(holiday.scheduleDate, DateTime(2026, 9, 29));
    expect(holiday.events, hasLength(1));
    expect(identical(holiday.events.single.event, event), isTrue);
    expect(holiday.events.single.actualWeekday, 2);
    expect(holiday.events.single.sourceWeekday, 2);
  });

  test('holiday display opt-in keeps the holiday marker without a source', () {
    final holiday = resolveAcademicCalendarDay(
      actualDate: DateTime(2026, 9, 29),
      schedules: const <ScheduleData>[],
      calendar: _calendar(),
      includeHolidayEvents: true,
    );

    expect(holiday.isHoliday, isTrue);
    expect(holiday.events, isEmpty);
  });

  test(
    'snapshot accepts published wire format and rejects incomplete response',
    () {
      final snapshot = AcademicCalendarSnapshot.fromJson({
        'success': true,
        'data': {
          'schema_version': 1,
          'year_term': '2026-2027-1',
          'revision': 'sha256:r1',
          'generated_at': '2026-09-19T10:00:00+08:00',
          'term_calendar_complete': true,
          'days': [
            {'date': '2026-09-25', 'kind': 'holiday', 'label': '中秋节'},
            {
              'date': '2026-09-26',
              'kind': 'teaching_day',
              'schedule_date': '2026-09-29',
              'label': '国庆调休补课',
            },
          ],
        },
      });
      expect(
        snapshot.dayAt(DateTime(2026, 9, 26))?.scheduleDate,
        DateTime(2026, 9, 29),
      );
      expect(
        () => AcademicCalendarSnapshot.fromJson({
          'year_term': '2026-2027-1',
          'revision': 'r',
          'generated_at': '2026-09-19T10:00:00+08:00',
          'term_calendar_complete': false,
          'days': [],
        }),
        throwsFormatException,
      );
    },
  );

  test('snapshot rejects unsupported and malformed day rules', () {
    Map<String, dynamic> wire(List<Map<String, dynamic>> days) => {
      'schema_version': 1,
      'year_term': '2026-2027-1',
      'revision': 'r1',
      'generated_at': '2026-09-19T10:00:00+08:00',
      'term_calendar_complete': true,
      'days': days,
    };

    expect(
      () => AcademicCalendarSnapshot.fromJson({
        ...wire(const []),
        'schema_version': 2,
      }),
      throwsFormatException,
    );
    expect(
      () => AcademicCalendarSnapshot.fromJson(
        wire([
          {
            'date': '2026-09-25',
            'kind': 'holiday',
            'schedule_date': '2026-09-26',
          },
        ]),
      ),
      throwsFormatException,
    );
    expect(
      () => AcademicCalendarSnapshot.fromJson(
        wire([
          {'date': '2026-09-26', 'kind': 'teaching_day'},
        ]),
      ),
      throwsFormatException,
    );
  });
}

ScheduleData _schedule(String week, List<EventItem> events) => ScheduleData(
  yearTerm: '2026-2027-1',
  weekNum: week,
  weekDayList: [
    WeekDayItem(weekDay: '1', weekDate: '2026-09-28'),
    WeekDayItem(weekDay: '2', weekDate: '2026-09-29'),
    WeekDayItem(weekDay: '6', weekDate: '2026-10-03'),
  ],
  eventList: events,
);

AcademicCalendarSnapshot _calendar() => AcademicCalendarSnapshot(
  schemaVersion: 1,
  yearTerm: '2026-2027-1',
  revision: 'r1',
  generatedAt: DateTime(2026, 9, 19),
  complete: true,
  days: [
    AcademicCalendarDay(
      date: DateTime(2026, 9, 29),
      kind: AcademicCalendarDayKind.holiday,
      label: '国庆节',
    ),
  ],
);
