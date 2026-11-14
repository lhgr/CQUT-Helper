import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_grid.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'failed missing week offers retry while cached week remains visible',
    (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      final retries = <String>[];
      Widget page(Map<int, ScheduleData> cache) => MaterialApp(
        home: Scaffold(
          body: SchedulePageView(
            pageController: controller,
            onPageChanged: (_) {},
            onScrollActivityChanged: (_) {},
            weekList: const ['1'],
            weekCache: cache,
            failedWeeks: const {1},
            onRetryWeek: retries.add,
            todayDate: DateTime(2026, 9, 29),
            showWeekend: true,
            weekendNoticeDismissed: false,
            onDismissWeekendNotice: () {},
            onBoundaryMessage: (_) {},
            currentWeekIndex: 0,
            onEditCourse: (_) async {},
            onDeleteCourse: (_) async {},
          ),
        ),
      );
      await tester.pumpWidget(page({}));
      expect(find.text('第1周加载失败'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('重试'));
      expect(retries, ['1']);
      await tester.pumpWidget(page({1: _week('1', DateTime(2026, 9, 28))}));
      expect(find.text('第1周加载失败'), findsNothing);
      expect(find.byType(ScheduleCourseGrid), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

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
            todayDate: DateTime(2026, 9, 29),
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

  testWidgets('临时显示补课周末保留每列最小宽度且关闭提示可点击', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 500));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = PageController();
    addTearDown(controller.dispose);
    var currentPage = 0;
    var noticeDismissed = false;
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
            todayDate: DateTime(2026, 9, 29),
            showWeekend: false,
            weekendNoticeDismissed: false,
            onDismissWeekendNotice: () => noticeDismissed = true,
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
    expect(makeupGrid.width! / 7, greaterThanOrEqualTo(52));
    expect(makeupGrid.width, greaterThan(normalGrid.width!));
    final close = find.byTooltip('关闭全部周末补课提示');
    expect(tester.getRect(close).right, lessThanOrEqualTo(360));
    await tester.ensureVisible(close);
    expect(tester.getSize(close).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(close).height, greaterThanOrEqualTo(48));
    await tester.tap(close);
    expect(noticeDismissed, isTrue);
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
