import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('重叠课程显示明确冲突提示并可打开完整课程列表', (tester) async {
    SharedPreferences.setMockInitialValues({'account': 'student'});
    CourseColorAssignmentManager.instance.resetInMemoryCache();
    final events = [
      EventItem(
        eventID: 'course-a',
        eventName: '数据结构',
        weekDay: '1',
        sessionStart: '1',
        sessionLast: '2',
        address: '博园101',
        memberName: '张老师',
      ),
      EventItem(
        eventID: 'course-b',
        eventName: '编译原理',
        weekDay: '1',
        sessionStart: '1',
        sessionLast: '2',
        address: '博园102',
        memberName: '李老师',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ScheduleCourseGrid(
              events: events,
              yearTerm: '2026-2027-1',
              sessionCount: 4,
              showWeekend: false,
              backgroundColors: const [Color(0xfffff3e0)],
              borderColors: const [Color(0xffe65100)],
              titleColors: const [Color(0xff6d2c00)],
              descriptionColors: const [Color(0xff8a3d00)],
              buttonColors: const [Color(0xffe65100)],
              onEditCourse: (_) async {},
              onDeleteCourse: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('冲突 +1'), findsOneWidget);

    await tester.tap(find.text('冲突 +1'));
    await tester.pumpAndSettle();

    expect(find.text('周一 1-2节 有 2 门课程'), findsOneWidget);
    expect(find.text('数据结构'), findsWidgets);
    expect(find.text('编译原理'), findsWidgets);
    expect(find.text('点击课程可查看详情'), findsOneWidget);
  });
}
