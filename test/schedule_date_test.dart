import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleDate.dataCoversDate', () {
    test(
      'stale today marker cannot make an old week cover the target date',
      () {
        final data = ScheduleData(
          weekDayList: [
            WeekDayItem(weekDate: '2026-08-03', today: true),
            WeekDayItem(weekDate: '2026-08-09'),
          ],
        );

        expect(
          ScheduleDate.dataCoversDate(data, DateTime(2026, 8, 10)),
          isFalse,
        );
      },
    );

    test('target date inside the parsed week range is covered', () {
      final data = ScheduleData(
        weekDayList: [
          WeekDayItem(weekDate: '2026-08-10'),
          WeekDayItem(weekDate: '2026-08-16'),
        ],
      );

      expect(ScheduleDate.dataCoversDate(data, DateTime(2026, 8, 12)), isTrue);
    });

    test('month-day week dates remain strict across a year boundary', () {
      final data = ScheduleData(
        weekDayList: [
          WeekDayItem(weekDate: '12-29', today: true),
          WeekDayItem(weekDate: '01-04'),
        ],
      );

      expect(ScheduleDate.dataCoversDate(data, DateTime(2026, 1, 2)), isTrue);
      expect(ScheduleDate.dataCoversDate(data, DateTime(2026, 1, 5)), isFalse);
    });

    test('unparseable dates are not rescued by today marker', () {
      final data = ScheduleData(
        weekDayList: [WeekDayItem(weekDate: '', today: true)],
      );

      expect(ScheduleDate.dataCoversDate(data, DateTime(2026, 8, 10)), isFalse);
    });

    test('invalid calendar dates are rejected instead of normalized', () {
      final data = ScheduleData(
        weekDayList: [
          WeekDayItem(weekDate: '2026-02-31', today: true),
          WeekDayItem(weekDate: '2026-03-06'),
        ],
      );

      expect(
        ScheduleDate.tryParseWeekDate(
          '2026-02-31',
          reference: DateTime(2026, 3, 3),
        ),
        isNull,
      );
      expect(ScheduleDate.dataCoversDate(data, DateTime(2026, 3, 3)), isFalse);
      expect(ScheduleDate.tryParseWeekDate('today=2026-02-28'), isNull);
      expect(
        ScheduleDate.tryParseWeekDate('2026-02-28T08:00:00+08:00'),
        isNull,
      );
    });
  });
}
