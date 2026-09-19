import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/widget_calendar_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('projects holiday and teaching day from the Flutter resolver', () {
    final source = ScheduleData(
      yearTerm: '2026-2027-1',
      weekNum: '5',
      weekDayList: [
        WeekDayItem(weekDay: '2', weekDate: '2026-09-29'),
        WeekDayItem(weekDay: '6', weekDate: '2026-10-03'),
      ],
      eventList: [
        EventItem(
          eventName: '高等数学',
          weekDay: '2',
          sessionStart: '1',
          sessionLast: '2',
        ),
      ],
    );
    final snapshot = AcademicCalendarSnapshot(
      schemaVersion: 1,
      yearTerm: '2026-2027-1',
      revision: 'sha256:test',
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

    final projection = WidgetCalendarProjection.build(
      yearTerm: snapshot.yearTerm,
      schedules: [source],
      calendar: snapshot,
      generatedAt: DateTime(2026, 9, 19),
    );
    final days = {
      for (final day in projection['days'] as List) day['date'] as String: day,
    };

    expect((days['2026-09-29'] as Map)['kind'], 'holiday');
    expect((days['2026-09-29'] as Map)['events'], isEmpty);
    expect((days['2026-09-26'] as Map)['kind'], 'teaching_day');
    expect((days['2026-09-26'] as Map)['source_date'], '2026-09-29');
    expect((days['2026-09-26'] as Map)['events'], hasLength(1));
    expect(
      ((days['2026-09-26'] as Map)['events'] as List).single['eventName'],
      '高等数学',
    );
  });

  test('marks a teaching day with an unavailable source week', () {
    final snapshot = AcademicCalendarSnapshot(
      schemaVersion: 1,
      yearTerm: '2026-2027-1',
      revision: 'sha256:test',
      generatedAt: DateTime(2026, 9, 19),
      complete: true,
      days: [
        AcademicCalendarDay(
          date: DateTime(2026, 9, 26),
          kind: AcademicCalendarDayKind.teachingDay,
          scheduleDate: DateTime(2026, 9, 29),
          label: '调休补课',
        ),
      ],
    );
    final projection = WidgetCalendarProjection.build(
      yearTerm: snapshot.yearTerm,
      schedules: const [],
      calendar: snapshot,
      generatedAt: DateTime(2026, 9, 19),
    );
    final day = (projection['days'] as List).single as Map;
    expect(day['kind'], 'missing_source');
    expect(day['events'], isEmpty);
  });
}
