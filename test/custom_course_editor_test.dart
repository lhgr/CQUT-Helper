import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/custom_course_editor_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingScheduleApi extends ScheduleApi {
  int addCalls = 0;
  int editCalls = 0;
  String? eventId;
  List<int>? weeks;
  int? sessionCount;

  @override
  Future<void> addCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String yearTerm,
    required List<int> weekList,
    required int weekDay,
    required int sessionStart,
    required int sessionCount,
    required String eventName,
    required String address,
    required String memberName,
  }) async {
    addCalls++;
    weeks = weekList;
    this.sessionCount = sessionCount;
  }

  @override
  Future<void> editCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String eventId,
    required List<int> weekList,
    required int weekDay,
    required int sessionStart,
    required int sessionCount,
    required String eventName,
    required String address,
    required String memberName,
  }) async {
    editCalls++;
    this.eventId = eventId;
    weeks = weekList;
    this.sessionCount = sessionCount;
  }
}

void main() {
  testWidgets('new custom course is saved through the school schedule API', (
    tester,
  ) async {
    final api = _RecordingScheduleApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomCourseEditorPage(
          userId: '20260001',
          encryptedPassword: 'secret',
          yearTerm: '2026-2027-1',
          availableWeeks: const [1, 2, 3],
          api: api,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'Linear Algebra');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.addCalls, 1);
    expect(api.editCalls, 0);
    expect(api.weeks, [1, 2, 3]);
    expect(api.sessionCount, 2);
  });

  testWidgets('existing custom course is edited by server event ID', (
    tester,
  ) async {
    final api = _RecordingScheduleApi();
    await tester.pumpWidget(
      MaterialApp(
        home: CustomCourseEditorPage(
          userId: '20260001',
          encryptedPassword: 'secret',
          yearTerm: '2026-2027-1',
          availableWeeks: const [1, 2, 3],
          initial: EventItem(
            eventID: 'server-event-id',
            eventName: 'Linear Algebra',
            weekList: const ['2', '3'],
            weekDay: '4',
            sessionStart: '5',
            sessionLast: '2',
          ),
          api: api,
        ),
      ),
    );

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.addCalls, 0);
    expect(api.editCalls, 1);
    expect(api.eventId, 'server-event-id');
    expect(api.weeks, [2, 3]);
  });
}
