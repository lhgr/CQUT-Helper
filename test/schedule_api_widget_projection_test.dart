import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScheduleApi.isWidgetProjectionVisible', () {
    test('pinned week and both adjacent weeks can affect widget content', () {
      for (final week in const ['5', '6', '7']) {
        expect(
          ScheduleApi.isWidgetProjectionVisible(
            yearTerm: '2026-2027-1',
            weekNum: week,
            pinnedYearTerm: '2026-2027-1',
            pinnedWeekNum: '6',
          ),
          isTrue,
          reason: 'week $week belongs to the visible projection window',
        );
      }
    });

    test('a distant week or another term cannot affect widget content', () {
      expect(
        ScheduleApi.isWidgetProjectionVisible(
          yearTerm: '2026-2027-1',
          weekNum: '8',
          pinnedYearTerm: '2026-2027-1',
          pinnedWeekNum: '6',
        ),
        isFalse,
      );
      expect(
        ScheduleApi.isWidgetProjectionVisible(
          yearTerm: '2026-2027-2',
          weekNum: '6',
          pinnedYearTerm: '2026-2027-1',
          pinnedWeekNum: '6',
        ),
        isFalse,
      );
    });
  });
}
