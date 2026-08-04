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
}
