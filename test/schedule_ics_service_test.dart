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
}
