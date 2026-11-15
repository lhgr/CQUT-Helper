import 'dart:math' as math;

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  for (final scale in [1.0, 2.0, 3.0]) {
    testWidgets('$scale倍日期保留每侧4留白且无需缩小文字', (tester) async {
      final data = ScheduleData(
        nowMonth: '11',
        weekDayList: [
          for (var day = 1; day <= 7; day++)
            WeekDayItem(
              weekDay: '$day',
              weekDate: '11-${(8 + day).toString().padLeft(2, '0')}',
            ),
        ],
      );
      var dayWidth = 0.0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale), boldText: true),
            child: child!,
          ),
          home: Builder(
            builder: (context) {
              dayWidth = math.max(
                52,
                ScheduleHeader.minimumDayWidth(
                  context,
                  scheduleData: data,
                  reference: DateTime(2026, 11, 9),
                ),
              );
              return Scaffold(
                body: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 35 + dayWidth * 7,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ScheduleHeader(
                        scheduleData: data,
                        todayDate: DateTime(2026, 11, 9),
                        timeColumnWidth: 35,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      final date = find.text('11-09');
      final cell = find
          .ancestor(of: date, matching: find.byType(Container))
          .first;
      final dateRect = tester.getRect(date);
      final cellRect = tester.getRect(cell);
      expect(dateRect.left - cellRect.left, greaterThanOrEqualTo(3.99));
      expect(cellRect.right - dateRect.right, greaterThanOrEqualTo(3.99));
      expect(cellRect.width, closeTo(dayWidth, 0.01));
      expect(
        find.descendant(
          of: find.byType(ScheduleHeader),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('图片上的月份与全部日期背景透明且大字自然增高', (tester) async {
    final data = ScheduleData(
      nowMonth: '11',
      weekDayList: [
        for (var day = 1; day <= 7; day++)
          WeekDayItem(weekDay: '$day', weekDate: '11-${15 + day}'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width:
                        30 +
                        ScheduleHeader.minimumDayWidth(
                              context,
                              scheduleData: data,
                              reference: DateTime(2026, 11, 16),
                            ) *
                            7,
                    child: ScheduleHeader(
                      scheduleData: data,
                      todayDate: DateTime(2026, 11, 16),
                      transparentBackground: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final header = find.byType(ScheduleHeader);
    final surface = tester.widget<Container>(
      find.descendant(of: header, matching: find.byType(Container)).first,
    );
    expect((surface.decoration! as BoxDecoration).color, Colors.transparent);
    expect(tester.getSize(header).height, greaterThanOrEqualTo(50));
    for (final text in ['11\n月', '周1', '周7']) {
      expect(
        tester.getRect(find.text(text)).bottom,
        lessThanOrEqualTo(tester.getRect(header).bottom),
      );
    }
    expect(tester.takeException(), isNull);
  });
}
