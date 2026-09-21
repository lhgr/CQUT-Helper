import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_grid.dart';
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
            weekendNoticeDismissed: false,
            onDismissWeekendNotice: () {},
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

  testWidgets('关闭周末时调休周与普通周保持相同的窄视口宽度', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PageController();
    addTearDown(controller.dispose);
    var currentPage = 0;
    final normal = _week('1', DateTime(2026, 9, 28));
    final makeup = _week('2', DateTime(2026, 10, 5));
    final calendar = AcademicCalendarSnapshot(
      schemaVersion: 1,
      yearTerm: '2026-2027-1',
      revision: 'r1',
      generatedAt: DateTime(2026, 9, 20),
      complete: true,
      days: [
        AcademicCalendarDay(
          date: DateTime(2026, 10, 10),
          kind: AcademicCalendarDayKind.teachingDay,
          scheduleDate: DateTime(2026, 10, 6),
          label: '调休补课',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SchedulePageView(
            pageController: controller,
            onPageChanged: (index) => currentPage = index,
            onScrollActivityChanged: (_) {},
            weekList: const ['1', '2'],
            weekCache: {1: normal, 2: makeup},
            showWeekend: false,
            weekendNoticeDismissed: false,
            onDismissWeekendNotice: () {},
            academicCalendar: calendar,
            onBoundaryMessage: (_) {},
            currentWeekIndex: 0,
            onEditCourse: (_) async {},
            onDeleteCourse: (_) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final normalGrid = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.byType(ScheduleCourseGrid),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(normalGrid.width, 325);

    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(currentPage, 1);
    expect(find.text('本周有周末补课，已临时显示周末课表'), findsOneWidget);
    final makeupGrid = tester.widget<SizedBox>(
      find
          .ancestor(
            of: find.byType(ScheduleCourseGrid),
            matching: find.byType(SizedBox),
          )
          .first,
    );
    expect(makeupGrid.width, normalGrid.width);
  });
}

ScheduleData _week(String week, DateTime monday) => ScheduleData(
  yearTerm: '2026-2027-1',
  weekNum: week,
  weekDayList: [
    for (var i = 0; i < 7; i++)
      WeekDayItem(
        weekDay: '${i + 1}',
        weekDate: monday
            .add(Duration(days: i))
            .toIso8601String()
            .substring(5, 10),
      ),
  ],
  eventList: [
    EventItem(
      weekNum: week,
      weekDay: '2',
      sessionList: const ['1'],
      eventName: '测试课程',
    ),
  ],
);
