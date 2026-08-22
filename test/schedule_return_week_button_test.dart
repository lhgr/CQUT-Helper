import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_return_week_button.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('shouldShowScheduleReturnWeekButton', () {
    test('本学期显示非本周时显示按钮', () {
      expect(
        shouldShowScheduleReturnWeekButton(
          displayedWeek: '3',
          displayedTerm: '2026-2027-1',
          actualCurrentWeek: '6',
          actualCurrentTerm: '2026-2027-1',
          displayedScheduleCoversToday: false,
        ),
        isTrue,
      );
    });

    test('当前周锚点暂时缺失时根据日期覆盖兜底', () {
      expect(
        shouldShowScheduleReturnWeekButton(
          displayedWeek: '3',
          displayedTerm: '2026-2027-1',
          actualCurrentWeek: null,
          actualCurrentTerm: null,
          displayedScheduleCoversToday: false,
        ),
        isTrue,
      );
      expect(
        shouldShowScheduleReturnWeekButton(
          displayedWeek: '6',
          displayedTerm: '2026-2027-1',
          actualCurrentWeek: null,
          actualCurrentTerm: null,
          displayedScheduleCoversToday: true,
        ),
        isFalse,
      );
    });
  });
}
