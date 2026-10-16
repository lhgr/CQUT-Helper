import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('widget and schedule fallback agree for UTF-16 course names', () {
    const size = 21;
    expect(
      CourseColorAssignmentManager.fallbackIndexForCourseKey('编译原理', size),
      3,
    );
    expect(
      CourseColorAssignmentManager.fallbackIndexForCourseKey('📚程序设计', size),
      4,
    );
    expect(CourseColorAssignmentManager.fallbackIndexForCourseKey('', size), 4);
    expect(
      CourseColorAssignmentManager.fallbackIndexForCourseKey('软件工程', size),
      19,
    );
  });
}
