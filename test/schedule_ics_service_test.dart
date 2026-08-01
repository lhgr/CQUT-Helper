import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/local_schedule_model.dart';
import 'package:cqut_helper/utils/schedule_ics_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final timeInfo = <CampusTimeInfo>[
    CampusTimeInfo(sessionNum: 1, startTime: '08:00', endTime: '08:45'),
    CampusTimeInfo(sessionNum: 2, startTime: '08:55', endTime: '09:40'),
    CampusTimeInfo(sessionNum: 3, startTime: '10:10', endTime: '10:55'),
  ];

  test('parses standard ICS events into dated local schedule events', () {
    const ics = '''BEGIN:VCALENDAR\r
VERSION:2.0\r
BEGIN:VEVENT\r
DTSTART:20260914T080000\r
DTEND:20260914T094000\r
SUMMARY:Discrete Mathematics\r
LOCATION:Building A\\, 201\r
DESCRIPTION:Bring workbook\\nChapter 1\r
END:VEVENT\r
BEGIN:VEVENT\r
DTSTART:invalid\r
SUMMARY:Skipped\r
END:VEVENT\r
END:VCALENDAR\r
''';

    final result = ScheduleIcsService.parse(
      content: ics,
      userId: '20260001',
      yearTerm: '2026-2027-1',
      timeInfo: timeInfo,
    );

    expect(result.events, hasLength(1));
    expect(result.skipped, 1);
    final event = result.events.single;
    expect(event.source, LocalScheduleSource.ics);
    expect(event.title, 'Discrete Mathematics');
    expect(event.location, 'Building A, 201');
    expect(event.note, 'Bring workbook\nChapter 1');
    expect(event.specificDate, DateTime(2026, 9, 14));
    expect(event.weekDay, DateTime.monday);
    expect(event.startSession, 1);
    expect(event.sessionCount, 2);
  });

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
}
