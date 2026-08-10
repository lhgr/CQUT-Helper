import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_return_week_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('课表背景启用时返回本周按钮使用透明背景', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ScheduleReturnWeekButton(
            onPressed: () {},
            transparentBackground: true,
          ),
        ),
      ),
    );

    final button = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(button.backgroundColor, Colors.transparent);
    expect(button.foregroundColor, isNotNull);
    expect(button.shape, isA<RoundedRectangleBorder>());
  });

  testWidgets('没有课表背景时返回本周按钮保留主题默认样式', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          floatingActionButton: ScheduleReturnWeekButton(
            onPressed: () {},
            transparentBackground: false,
          ),
        ),
      ),
    );

    final button = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    expect(button.backgroundColor, isNull);
    expect(button.foregroundColor, isNull);
    expect(button.shape, isNull);
  });
}
