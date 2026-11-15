import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/exam_model.dart';
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

  testWidgets(
    'cached weeks are indexed once and in-place course updates remain visible',
    (tester) async {
      final controller = PageController(initialPage: 19);
      addTearDown(controller.dispose);
      final weeks = <int, ScheduleData>{
        for (var week = 1; week <= 20; week++)
          week: _week(
            '$week',
            DateTime(2026, 9, 7).add(Duration(days: (week - 1) * 7)),
          ),
      };
      final countedDays = <_CountingWeekDay>[];
      for (final data in weeks.values) {
        data.weekDayList = [
          for (final day in data.weekDayList!)
            _CountingWeekDay(day.weekDay!, day.weekDate!),
        ];
        countedDays.addAll(data.weekDayList!.cast<_CountingWeekDay>());
      }
      Widget page() => MaterialApp(
        home: Scaffold(
          body: SchedulePageView(
            pageController: controller,
            onPageChanged: (_) {},
            onScrollActivityChanged: (_) {},
            weekList: [for (var week = 1; week <= 20; week++) '$week'],
            weekCache: weeks,
            todayDate: DateTime(2026, 9, 29),
            showWeekend: true,
            weekendNoticeDismissed: false,
            onDismissWeekendNotice: () {},
            onBoundaryMessage: (_) {},
            currentWeekIndex: 19,
            onEditCourse: (_) async {},
            onDeleteCourse: (_) async {},
          ),
        ),
      );
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      // The first 18 weeks supply lookup dates only; resolving the displayed
      // week must not repeatedly parse them once for each of its seven days.
      for (final day in countedDays.take(18 * 7)) {
        expect(day.reads, 1);
      }
      final grid = tester.widget<ScheduleCourseGrid>(
        find.byType(ScheduleCourseGrid),
      );
      expect(grid.events.single, same(weeks[20]!.eventList!.single));
      weeks[20]!.eventList!.single.eventName = '修改后的课程';
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('修改后的课程'), findsWidgets);
      weeks[20]!.eventList!.clear();
      await tester.pumpWidget(page());
      await tester.pumpAndSettle();
      expect(find.text('本周无课'), findsOneWidget);
    },
  );
  testWidgets('短屏大字体下合并周末说明，关闭补课说明保留考试说明', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 240));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var dismissed = false;
    var restored = false;
    final week = _week('1', DateTime(2026, 10, 5));
    final exam = ExamRecord(
      key: 'weekend',
      courseName: '考试课程',
      timeText: '09:00-11:00',
      campus: '',
      building: '',
      room: '',
      startAt: DateTime.parse('2026-10-10T09:00:00+08:00'),
      endAt: DateTime.parse('2026-10-10T11:00:00+08:00'),
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SchedulePageView(
              pageController: null,
              onPageChanged: (_) {},
              onScrollActivityChanged: (_) {},
              weekList: const ['1'],
              weekCache: {1: week},
              todayDate: DateTime(2026, 10, 5),
              showWeekend: false,
              weekendNoticeDismissed: dismissed,
              onDismissWeekendNotice: () => setState(() => dismissed = true),
              onRestoreExamTimeAxis: () => restored = true,
              exams: [exam],
              academicCalendar: AcademicCalendarSnapshot(
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
              ),
              onBoundaryMessage: (_) {},
              currentWeekIndex: 0,
              onEditCourse: (_) async {},
              onDeleteCourse: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('本周有周末补课和考试，已临时显示周末课表'), findsOneWidget);
    await tester.ensureVisible(find.text('重新获取作息'));
    await tester.tap(find.text('重新获取作息'));
    expect(restored, isTrue);
    final close = find.byTooltip('关闭全部周末补课提示');
    await tester.ensureVisible(close);
    await tester.tap(close);
    await tester.pumpAndSettle();
    expect(find.text('本周有周末考试，已临时显示周末'), findsOneWidget);
    expect(find.text('本周有周末补课和考试，已临时显示周末课表'), findsNothing);
    expect(
      tester
          .widget<ScheduleCourseGrid>(find.byType(ScheduleCourseGrid))
          .showWeekend,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  for (final boldText in [false, true]) {
    testWidgets('真实周课表为课程与并排考试保留可读列宽 boldText=$boldText', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 480));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final week = _week('1', DateTime(2026, 10, 5));
      week.eventList = [
        for (var i = 0; i < 2; i++)
          EventItem(
            eventName: '课程$i',
            weekDay: '1',
            sessionStart: '2',
            sessionLast: '2',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2), boldText: boldText),
            child: child!,
          ),
          home: Scaffold(
            body: SchedulePageView(
              pageController: null,
              onPageChanged: (_) {},
              onScrollActivityChanged: (_) {},
              weekList: const ['1'],
              weekCache: {1: week},
              todayDate: DateTime(2026, 10, 5),
              showWeekend: true,
              weekendNoticeDismissed: false,
              onDismissWeekendNotice: () {},
              timeInfoList: [
                for (var i = 0; i < 10; i++)
                  CampusTimeInfo(
                    sessionNum: i + 1,
                    startTime: '${8 + i}:00',
                    endTime: '${8 + i}:45',
                  ),
              ],
              exams: [
                for (var i = 0; i < 3; i++)
                  ExamRecord(
                    key: 'parallel$i',
                    courseName: '考试课程$i',
                    timeText: '09:00-11:00',
                    campus: '',
                    building: '',
                    room: '101',
                    startAt: DateTime.parse('2026-10-05T09:00:00+08:00'),
                    endAt: DateTime.parse('2026-10-05T11:00:00+08:00'),
                  ),
              ],
              onBoundaryMessage: (_) {},
              currentWeekIndex: 0,
              onEditCourse: (_) async {},
              onDeleteCourse: (_) async {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final grid = find.byType(ScheduleCourseGrid);
      final card = find.byKey(const ValueKey('exam-card-parallel0'));
      // Two overlapping courses share their existing group lane; exams add three lanes.
      final gridWidth = tester.getSize(grid).width;
      expect(tester.getSize(card).width, closeTo(gridWidth / 7 / 4, 0.01));
      expect(tester.getSize(card).width, greaterThanOrEqualTo(72));
      final time = find.byKey(const ValueKey('exam-time-parallel0'));
      final fitted = find
          .ancestor(of: time, matching: find.byType(FittedBox))
          .first;
      expect(
        tester.getSize(time).width,
        lessThanOrEqualTo(tester.getSize(fitted).width),
      );
      expect(find.text('考试 · 考试课程0'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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

class _CountingWeekDay extends WeekDayItem {
  _CountingWeekDay(String day, String date)
    : super(weekDay: day, weekDate: date);

  int reads = 0;

  @override
  String? get weekDate {
    reads++;
    return super.weekDate;
  }
}
