import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/course_detail_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('课程详情统一提供编辑操作', (tester) async {
    var edited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCourseDetailDialog(
              context,
              courseName: '普通课程',
              events: [EventItem(eventName: '普通课程')],
              onEdit: (_) async => edited = true,
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.event_available_outlined), findsNothing);
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsNothing);
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(edited, isTrue);
  });

  testWidgets('学校自定义课程详情额外提供删除操作', (tester) async {
    var deletedEventId = '';
    final event = EventItem(
      eventName: '自定义课程',
      eventType: '3',
      eventID: 'server-event-id',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showCourseDetailDialog(
              context,
              courseName: '自定义课程',
              events: [event],
              onEdit: (_) async {},
              onDelete: (selected) async {
                deletedEventId = selected.eventID ?? '';
              },
            ),
            child: const Text('打开'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletedEventId, 'server-event-id');
  });

  test('只有带服务端 ID 的 type=3 课程属于学校自定义课程', () {
    expect(
      EventItem(eventType: '3', eventID: 'server-id').isSchoolCustomCourse,
      isTrue,
    );
    expect(EventItem(eventType: '3').isSchoolCustomCourse, isFalse);
    expect(
      EventItem(eventType: '1', eventID: 'server-id').isSchoolCustomCourse,
      isFalse,
    );
  });
}
