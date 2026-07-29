import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_app_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('学期信息与最后更新时间分开展示', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ScheduleAppBar(
            loading: false,
            weekList: const ['1', '2', '3'],
            currentWeekIndex: 1,
            currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
            refreshStatusText: '今天 23:12更新',
            onRefresh: () {},
            onSettings: () {},
            onWeekPicker: () {},
            onTermPicker: () {},
            onSemesterCourses: () {},
          ),
        ),
      ),
    );

    expect(find.text('第2周'), findsOneWidget);
    expect(find.text('2026-2027-1学期'), findsOneWidget);
    expect(find.text('23:12'), findsOneWidget);
    expect(find.textContaining('2026-2027-1学期 ·'), findsNothing);
  });

  testWidgets('非当天更新时间保留日期和时间', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ScheduleAppBar(
            loading: false,
            weekList: const ['1'],
            currentWeekIndex: 0,
            currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
            refreshStatusText: '9/11 23:12更新',
            onRefresh: () {},
            onSettings: () {},
            onWeekPicker: () {},
            onTermPicker: () {},
            onSemesterCourses: () {},
          ),
        ),
      ),
    );

    expect(find.text('9/11 23:12'), findsOneWidget);
  });
}
