import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('周页面滑动会报告交互开始与结束', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    final activity = <bool>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePageView(
            pageController: controller,
            onPageChanged: (_) {},
            onScrollActivityChanged: activity.add,
            weekList: const ['1', '2'],
            weekCache: const {},
            showWeekend: true,
            onBoundaryMessage: (_) {},
            currentWeekIndex: 0,
            onEditCourse: (_) async {},
            onDeleteCourse: (_) async {},
          ),
        ),
      ),
    );

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    for (var frame = 0; frame < 90 && !activity.contains(false); frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(activity, containsAllInOrder([true, false]));
  });
}
