import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/course_preference_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/hidden_courses_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HiddenCourseInfo hiddenCourse() {
    return HiddenCourseInfo(
      preference: CoursePreference(
        userId: 'u1',
        yearTerm: '2026-2027-1',
        courseKey: 'course:高等数学|张老师',
        displayName: null,
        teacher: null,
        location: null,
        note: '',
        hidden: true,
        reminderMinutes: null,
        colorIndex: null,
        updatedAt: DateTime(2026),
      ),
      cachedEvent: EventItem(
        eventName: '高等数学',
        memberName: '张老师',
        address: '2-101',
      ),
    );
  }

  testWidgets('隐藏课程列表可直接取消隐藏', (tester) async {
    final course = hiddenCourse();
    var restored = false;
    var loadCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HiddenCoursesSheet(
            userId: 'u1',
            yearTerm: '2026-2027-1',
            loadCourses: () async {
              loadCount++;
              return restored ? const [] : [course];
            },
            onRestore: (_) async => restored = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('张老师 · 2-101'), findsOneWidget);
    await tester.tap(find.text('取消隐藏'));
    await tester.pumpAndSettle();

    expect(restored, isTrue);
    expect(loadCount, 2);
    expect(find.text('暂无隐藏课程'), findsOneWidget);
  });

  test('隐藏课程信息优先使用本地偏好和缓存', () {
    final course = hiddenCourse();
    expect(course.displayName, '高等数学');
    expect(course.teacher, '张老师');
    expect(course.location, '2-101');
  });
}
