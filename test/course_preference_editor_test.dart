import 'package:cqut_helper/model/course_preference_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/course_preference_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> openEditor(
    WidgetTester tester, {
    required ValueChanged<CoursePreference?> onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                final result = await showCoursePreferenceEditor(
                  context,
                  userId: '20260001',
                  yearTerm: '2026-2027-1',
                  courseKey: 'course:Calculus|Teacher A',
                  currentName: 'Calculus',
                  currentTeacher: 'Teacher A',
                  currentLocation: 'Room 201',
                  initial: null,
                );
                onResult(result);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  testWidgets('saving without changes closes cleanly and returns no override', (
    tester,
  ) async {
    CoursePreference? result;
    var completed = false;
    await openEditor(
      tester,
      onResult: (value) {
        result = value;
        completed = true;
      },
    );

    final saveButton = find.byType(FilledButton);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(completed, isTrue);
    expect(result, isNull);
  });

  testWidgets('only changed fields are returned as course overrides', (
    tester,
  ) async {
    CoursePreference? result;
    await openEditor(tester, onResult: (value) => result = value);

    await tester.enterText(find.byType(TextField).first, 'Advanced Calculus');
    final saveButton = find.byType(FilledButton);
    await tester.ensureVisible(saveButton);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(result?.displayName, 'Advanced Calculus');
    expect(result?.teacher, isNull);
    expect(result?.location, isNull);
  });
}
