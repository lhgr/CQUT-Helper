import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_card.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_grid.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_page_view.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_time_column.dart';
import 'package:cqut_helper/utils/exam_schedule_projection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

ExamRecord record(String key, int day) => ExamRecord(
  key: key,
  courseName: '考试$key',
  timeText: '09:00-11:00',
  campus: '两江',
  building: '教学楼',
  room: '101',
  startAt: DateTime.parse('2026-11-${day}T09:00:00+08:00'),
  endAt: DateTime.parse('2026-11-${day}T11:00:00+08:00'),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({'account': 'student'}));

  testWidgets(
    'course layers share exam lanes and keep conflict and exam taps',
    (tester) async {
      final examination = record('a', 16);
      final courses = [
        for (final name in ['课程甲', '课程乙'])
          EventItem(
            eventID: name,
            eventName: name,
            weekDay: '1',
            sessionStart: '1',
            sessionLast: '2',
          ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              child: ScheduleCourseGrid(
                events: courses,
                yearTerm: '2026-2027-1',
                showWeekend: false,
                exams: [ExamProjection(examination, 1, 0, 120)],
                backgroundColors: const [Colors.orange],
                borderColors: const [Colors.orange],
                titleColors: const [Colors.black],
                descriptionColors: const [Colors.black],
                buttonColors: const [Colors.orange],
                hideLocation: true,
                horizontalCenter: true,
                verticalCenter: true,
                cardRadius: 16,
                textScale: 1.2,
                cardOpacity: 0.6,
                onEditCourse: (_) async {},
                onDeleteCourse: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final cards = find.byWidgetPredicate(
        (widget) =>
            widget is ScheduleCourseCard && courses.contains(widget.event),
      );
      expect(cards, findsNWidgets(2));
      expect(tester.getRect(cards.first), tester.getRect(cards.last));
      final courseRect = tester.getRect(cards.last);
      final examRect = tester.getRect(
        find.byKey(const ValueKey('exam-card-a')),
      );
      final examCard = find.byKey(const ValueKey('exam-card-a'));
      final decoration =
          tester
                  .widget<Ink>(
                    find.descendant(of: examCard, matching: find.byType(Ink)),
                  )
                  .decoration!
              as BoxDecoration;
      expect(decoration.color!.a, closeTo(0.6, 0.01));
      expect(decoration.border, Border.all(color: Colors.orange));
      expect(decoration.borderRadius, BorderRadius.circular(16));
      final title = tester.widget<Text>(find.text('考试 · 考试a'));
      expect(title.style!.fontSize, 12);
      expect(title.textAlign, TextAlign.center);
      expect(
        find.descendant(
          of: examCard,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Text &&
                widget.semanticsLabel?.startsWith('地点：') == true,
          ),
        ),
        findsNothing,
      );
      expect(courseRect.right, lessThanOrEqualTo(examRect.left));
      expect(courseRect.width, lessThan(100));
      await tester.tap(cards.last);
      await tester.pumpAndSettle();
      expect(find.text('周一 1-2节 有 2 门课程'), findsOneWidget);
      Navigator.of(tester.element(find.text('周一 1-2节 有 2 门课程'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('exam-card-a')));
      await tester.pumpAndSettle();
      expect(find.text('考试a'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('两江 · 教学楼 · 101'),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    '32dp seven-column exam lanes reserve accurate time and stay inside lanes',
    (tester) async {
      final exams = [
        for (var i = 0; i < 3; i++)
          ExamProjection(record('narrow$i', 16), 1, 0, 32),
      ];
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!,
          ),
          home: Scaffold(
            body: SizedBox(
              width: 210,
              child: ScheduleCourseGrid(
                events: [
                  for (var i = 0; i < 6; i++)
                    EventItem(
                      eventID: 'c$i',
                      eventName: '课程$i',
                      weekDay: '1',
                      sessionStart: '1',
                      sessionLast: '2',
                    ),
                ],
                yearTerm: '2026-2027-1',
                exams: exams,
                showWeekend: true,
                backgroundColors: const [Colors.orange],
                borderColors: const [Colors.orange],
                titleColors: const [Colors.black],
                descriptionColors: const [Colors.black],
                buttonColors: const [Colors.orange],
                onEditCourse: (_) async {},
                onDeleteCourse: (_) async {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final courseRect = tester.getRect(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is ScheduleCourseCard &&
                  widget.event.eventID?.startsWith('c') == true,
            )
            .last,
      );
      final firstExamRect = tester.getRect(
        find.byKey(const ValueKey('exam-card-narrow0')),
      );
      expect(courseRect.right, lessThanOrEqualTo(firstExamRect.left));
      expect(firstExamRect.height, 32);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey('exam-time-narrow$i')), findsOneWidget);
        final time = tester.widget<Text>(
          find.byKey(ValueKey('exam-time-narrow$i')),
        );
        expect(time.data, '09:00–11:00');
        final rect = tester.getRect(find.byKey(ValueKey('exam-card-narrow$i')));
        expect(rect.right, lessThanOrEqualTo(30));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'weekend exams retain actual date through makeup mapping and hidden time labels',
    (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      final data = ScheduleData(
        yearTerm: '2026-2027-1',
        weekNum: '1',
        weekDayList: [
          for (var day = 16; day <= 22; day++)
            WeekDayItem(weekDay: '${day - 15}', weekDate: '2026-11-$day'),
        ],
        eventList: [],
      );
      final calendar = AcademicCalendarSnapshot(
        schemaVersion: 1,
        yearTerm: '2026-2027-1',
        revision: 'r1',
        generatedAt: DateTime(2026, 11, 1),
        complete: true,
        days: [
          AcademicCalendarDay(
            date: DateTime(2026, 11, 21),
            kind: AcademicCalendarDayKind.teachingDay,
            scheduleDate: DateTime(2026, 11, 17),
            label: '调休',
          ),
        ],
      );
      Widget page(List<CampusTimeInfo>? timeInfo) => MaterialApp(
        home: Scaffold(
          body: SchedulePageView(
            pageController: controller,
            onPageChanged: (_) {},
            onScrollActivityChanged: (_) {},
            weekList: const ['1'],
            weekCache: {1: data},
            todayDate: DateTime(2026, 11, 16),
            showWeekend: false,
            weekendNoticeDismissed: true,
            onDismissWeekendNotice: () {},
            onBoundaryMessage: (_) {},
            currentWeekIndex: 0,
            academicCalendar: calendar,
            timeInfoList: timeInfo,
            showTimeLabels: false,
            exams: [record('sat', 21), record('sun', 22)],
            onRestoreExamTimeAxis: () {},
            onEditCourse: (_) async {},
            onDeleteCourse: (_) async {},
          ),
        ),
      );
      await tester.pumpWidget(
        page([
          for (var i = 0; i < 10; i++)
            CampusTimeInfo(
              sessionNum: i + 1,
              startTime: '${8 + i}:00',
              endTime: '${8 + i}:45',
            ),
        ]),
      );
      await tester.pumpAndSettle();
      final grid = tester.widget<ScheduleCourseGrid>(
        find.byType(ScheduleCourseGrid),
      );
      expect(grid.showWeekend, isTrue);
      expect(grid.exams.map((exam) => exam.weekday), [6, 7]);
      expect(
        tester
            .widget<ScheduleTimeColumn>(find.byType(ScheduleTimeColumn))
            .timeInfoList,
        isNull,
      );
      await tester.pumpWidget(page(null));
      await tester.pumpAndSettle();
      expect(find.text('重新获取作息'), findsOneWidget);
      expect(find.text('查看考试'), findsOneWidget);
      expect(
        tester
            .widget<ScheduleCourseGrid>(find.byType(ScheduleCourseGrid))
            .exams,
        isEmpty,
      );
      for (final day in data.weekDayList!) {
        day.weekDate = day.weekDate!.substring(5);
      }
      await tester.pumpWidget(
        page([
          for (var i = 0; i < 10; i++)
            CampusTimeInfo(
              sessionNum: i + 1,
              startTime: '${8 + i}:00',
              endTime: '${8 + i}:45',
            ),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('exam-card-sat')), findsOneWidget);
      expect(find.byKey(const ValueKey('exam-card-sun')), findsOneWidget);
      expect(find.text('课表日期不完整，考试暂未显示在课表中'), findsNothing);
      data.yearTerm = null;
      await tester.pumpWidget(page(null));
      await tester.pumpAndSettle();
      expect(find.text('课表日期不完整，考试暂未显示在课表中'), findsOneWidget);
      expect(find.text('查看考试'), findsOneWidget);
    },
  );
}
