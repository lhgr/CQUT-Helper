import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/schedule_ics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timeInfo = <CampusTimeInfo>[
    CampusTimeInfo(sessionNum: 1, startTime: '08:00', endTime: '08:45'),
    CampusTimeInfo(sessionNum: 2, startTime: '08:55', endTime: '09:40'),
    CampusTimeInfo(sessionNum: 3, startTime: '10:10', endTime: '10:55'),
  ];

  test('generates a standards-shaped calendar with escaped fields', () {
    final schedule = ScheduleData(
      yearTerm: '2026-2027-1',
      weekNum: '1',
      weekDayList: [WeekDayItem(weekDay: '1', weekDate: '2026-09-14')],
      eventList: [
        EventItem(
          eventID: 'course-1',
          eventName: 'Math, Advanced',
          memberName: 'Teacher A',
          address: 'Room; 201',
          note: 'Review\nChapter 1',
          weekDay: '1',
          sessionStart: '1',
          sessionLast: '2',
          sessionList: const ['1', '2'],
        ),
      ],
    );

    final content = ScheduleIcsService.generate(
      schedules: [schedule],
      timeInfo: timeInfo,
    );

    expect(content, contains('BEGIN:VCALENDAR'));
    expect(content, contains('BEGIN:VEVENT'));
    expect(content, contains('DTSTART:20260914T080000'));
    expect(content, contains('DTEND:20260914T094000'));
    expect(content, contains(r'SUMMARY:Math\, Advanced'));
    expect(content, contains(r'LOCATION:Room\; 201'));
    expect(content, contains('END:VCALENDAR'));
  });

  test('reports an empty schedule instead of pretending it has events', () {
    final result = ScheduleIcsService.generateResult(
      schedules: [
        ScheduleData(
          yearTerm: '2026-2027-1',
          weekNum: '1',
          weekDayList: const [],
          eventList: const [],
        ),
      ],
      timeInfo: timeInfo,
    );

    expect(result.eventCount, 0);
    expect(result.sourceEventCount, 0);
    expect(result.skippedEventCount, 0);
    expect(result.content, isNot(contains('BEGIN:VEVENT')));
  });

  test('reports events skipped because their date is unavailable', () {
    final result = ScheduleIcsService.generateResult(
      schedules: [
        ScheduleData(
          yearTerm: '2026-2027-1',
          weekNum: '1',
          weekDayList: const [],
          eventList: [
            EventItem(
              eventName: 'Linear Algebra',
              weekDay: '1',
              sessionStart: '1',
              sessionLast: '2',
            ),
          ],
        ),
      ],
      timeInfo: timeInfo,
    );

    expect(result.eventCount, 0);
    expect(result.sourceEventCount, 1);
    expect(result.skippedEventCount, 1);
  });

  test('matches numeric event weekdays to Chinese weekday labels', () {
    final result = ScheduleIcsService.generateResult(
      schedules: [
        ScheduleData(
          yearTerm: '2026-2027-1',
          weekNum: '1',
          weekDayList: [
            WeekDayItem(weekDay: '一', weekDate: '2026-09-14'),
            WeekDayItem(weekDay: '周二', weekDate: '2026-09-15'),
            WeekDayItem(weekDay: '星期三', weekDate: '2026-09-16'),
          ],
          eventList: [
            EventItem(
              eventName: 'Linear Algebra',
              weekDay: '2',
              sessionStart: '1',
              sessionLast: '2',
            ),
          ],
        ),
      ],
      timeInfo: timeInfo,
    );

    expect(result.eventCount, 1);
    expect(result.skippedEventCount, 0);
    expect(result.content, contains('DTSTART:20260915T080000'));
  });

  test('uses weekday list order when the weekday label is absent', () {
    final result = ScheduleIcsService.generateResult(
      schedules: [
        ScheduleData(
          yearTerm: '2026-2027-1',
          weekNum: '1',
          weekDayList: [
            WeekDayItem(weekDate: '2026-09-14'),
            WeekDayItem(weekDate: '2026-09-15'),
          ],
          eventList: [
            EventItem(
              eventName: 'College English',
              weekDay: '2',
              sessionStart: '3',
              sessionLast: '1',
            ),
          ],
        ),
      ],
      timeInfo: timeInfo,
    );

    expect(result.eventCount, 1);
    expect(result.skippedEventCount, 0);
    expect(result.content, contains('DTSTART:20260915T101000'));
  });

  test('uses course reminder override before the exported default', () {
    final content = ScheduleIcsService.generate(
      schedules: [
        ScheduleData(
          weekDayList: [WeekDayItem(weekDay: '1', weekDate: '2026-09-14')],
          eventList: [
            EventItem(
              eventName: 'Signals, and Systems',
              weekDay: '1',
              sessionStart: '1',
              sessionLast: '1',
              reminderMinutes: 30,
            ),
          ],
        ),
      ],
      timeInfo: timeInfo,
      defaultReminderMinutes: 10,
    );

    expect(content, contains('BEGIN:VALARM'));
    expect(content, contains('TRIGGER:-PT30M'));
    expect(content, contains('ACTION:DISPLAY'));
    expect(content, contains(r'DESCRIPTION:Signals\, and Systems 即将开始'));
    expect(RegExp('BEGIN:VALARM').allMatches(content), hasLength(1));
  });

  test('uses the exported default when a course has no override', () {
    final content = ScheduleIcsService.generate(
      schedules: [
        ScheduleData(
          weekDayList: [WeekDayItem(weekDay: '1', weekDate: '2026-09-14')],
          eventList: [
            EventItem(
              eventName: 'Linear Algebra',
              weekDay: '1',
              sessionStart: '1',
              sessionLast: '1',
            ),
          ],
        ),
      ],
      timeInfo: timeInfo,
      defaultReminderMinutes: 15,
    );

    expect(content, contains('TRIGGER:-PT15M'));
  });

  test('zero reminder suppresses VALARM for that event', () {
    final content = ScheduleIcsService.generate(
      schedules: [
        ScheduleData(
          weekDayList: [WeekDayItem(weekDay: '1', weekDate: '2026-09-14')],
          eventList: [
            EventItem(
              eventName: 'No Alarm',
              weekDay: '1',
              sessionStart: '1',
              sessionLast: '1',
              reminderMinutes: 0,
            ),
          ],
        ),
      ],
      timeInfo: timeInfo,
      defaultReminderMinutes: 10,
    );

    expect(content, isNot(contains('BEGIN:VALARM')));
  });

  test('duplicate course occurrences emit only one event alarm', () {
    final duplicate = EventItem(
      eventID: 'duplicate-1',
      eventName: 'Duplicated Course',
      weekDay: '1',
      sessionStart: '1',
      sessionLast: '1',
    );
    final result = ScheduleIcsService.generateResult(
      schedules: [
        ScheduleData(
          weekDayList: [WeekDayItem(weekDay: '1', weekDate: '2026-09-14')],
          eventList: [duplicate],
        ),
        ScheduleData(
          weekDayList: [WeekDayItem(weekDay: '1', weekDate: '2026-09-14')],
          eventList: [duplicate],
        ),
      ],
      timeInfo: timeInfo,
      defaultReminderMinutes: 10,
    );

    expect(result.sourceEventCount, 2);
    expect(result.eventCount, 1);
    expect(RegExp('BEGIN:VALARM').allMatches(result.content), hasLength(1));
  });
}
