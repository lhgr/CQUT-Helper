import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_return_week_button.dart';
import 'package:flutter/material.dart';
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

  testWidgets('底部偏移使按钮避开外层导航栏', (tester) async {
    const navigationBarHeight = 80.0;
    const navigationBarBottomInset = 8.0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          extendBody: true,
          body: Scaffold(
            floatingActionButton: ScheduleReturnWeekButton(
              onPressed: () {},
              transparentBackground: false,
              bottomOffset: navigationBarHeight + navigationBarBottomInset,
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: navigationBarBottomInset),
            child: NavigationBar(
              height: navigationBarHeight,
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.calendar_today),
                  label: '课表',
                ),
                NavigationDestination(icon: Icon(Icons.person), label: '我的'),
              ],
            ),
          ),
        ),
      ),
    );

    final buttonRect = tester.getRect(find.byType(FloatingActionButton));
    final navigationBarRect = tester.getRect(find.byType(NavigationBar));

    expect(buttonRect.bottom, lessThanOrEqualTo(navigationBarRect.top - 16));
  });
}
