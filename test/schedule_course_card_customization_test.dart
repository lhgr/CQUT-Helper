import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('只移除花溪与两江校区前缀', () {
    expect(ScheduleCourseCard.removeKnownCampusPrefix('花溪校区 博园201'), '博园201');
    expect(
      ScheduleCourseCard.removeKnownCampusPrefix('两江校区·弘远楼A103'),
      '弘远楼A103',
    );
    expect(ScheduleCourseCard.removeKnownCampusPrefix('杨家坪校区 3教'), '杨家坪校区 3教');
  });

  testWidgets('课程卡片应用隐藏字段与居中设置', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 90,
            height: 140,
            child: ScheduleCourseCard(
              event: EventItem(
                eventName: '程序设计',
                address: '花溪校区 博园201',
                memberName: '张老师',
              ),
              backgroundColor: Colors.blue.shade50,
              borderColor: Colors.blue,
              titleColor: Colors.blue.shade900,
              descriptionColor: Colors.blue.shade700,
              onTap: () {},
              hideTeacher: true,
              removeCampusPrefix: true,
              horizontalCenter: true,
              verticalCenter: true,
              borderRadius: 20,
              textScale: 1.2,
              cardOpacity: 0.5,
            ),
          ),
        ),
      ),
    );

    final content = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((widget) => widget.textSpan != null);
    expect(content.textSpan!.toPlainText(), '程序设计\n博园201');
    expect(content.textAlign, TextAlign.center);

    final centered = tester
        .widgetList<Align>(find.byType(Align))
        .any((widget) => widget.alignment == Alignment.center);
    expect(centered, isTrue);

    final decoration = tester
        .widgetList<Container>(find.byType(Container))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((value) => value.border != null);
    expect(decoration.color!.a, closeTo(0.5, 0.01));
  });
}
