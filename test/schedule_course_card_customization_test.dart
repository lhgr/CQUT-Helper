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
        .widgetList<Ink>(find.byType(Ink))
        .map((widget) => widget.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((value) => value.border != null);
    expect(decoration.color!.a, closeTo(0.5, 0.01));
  });

  testWidgets('冲突卡片使用图标文字提示并提供按压反馈', (tester) async {
    var taps = 0;
    final event = EventItem(
      eventID: 'event-42',
      eventName: '操作系统',
      weekNum: '3',
      weekDay: '2',
      sessionStart: '3',
      sessionLast: '2',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 90,
            height: 80,
            child: ScheduleCourseCard(
              event: event,
              backgroundColor: Colors.orange.shade50,
              borderColor: Colors.deepOrange,
              titleColor: Colors.deepOrange.shade900,
              descriptionColor: Colors.deepOrange.shade700,
              conflictCount: 2,
              onTap: () => taps++,
            ),
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    expect(find.text('冲突 +2'), findsOneWidget);
    expect(
      find.byKey(ScheduleCourseCard.conflictIndicatorKeyForEvent(event)),
      findsOneWidget,
    );

    final interaction = find.byKey(
      ScheduleCourseCard.interactionKeyForEvent(event),
    );
    expect(interaction, findsOneWidget);
    expect(tester.widget<InkWell>(interaction).onTap, isNotNull);
    await tester.tap(interaction);
    await tester.pump();
    expect(taps, 1);
  });

  test('无服务端 ID 时交互键由课程位置稳定生成', () {
    final first = EventItem(
      eventName: '高等数学',
      weekNum: '1',
      weekDay: '1',
      sessionStart: '1',
      sessionLast: '2',
      memberName: '李老师',
    );
    final same = EventItem(
      eventName: '高等数学',
      weekNum: '1',
      weekDay: '1',
      sessionStart: '1',
      sessionLast: '2',
      memberName: '李老师',
    );

    expect(
      ScheduleCourseCard.interactionKeyForEvent(first),
      ScheduleCourseCard.interactionKeyForEvent(same),
    );
  });
}
