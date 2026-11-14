import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('长地点保留教学楼和房间号尾段，偏好与完整地址语义不丢失', (tester) async {
    const address = '花溪校区 学院工程实验综合教学中心及计算机开放实验区域弘远楼A302';
    final event = EventItem(eventName: '操作系统实验', address: address);
    Future<void> pump({bool remove = false, bool hide = false}) =>
        tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 90,
                  height: 100,
                  child: ScheduleCourseCard(
                    event: event,
                    backgroundColor: Colors.blue.shade50,
                    borderColor: Colors.blue,
                    titleColor: Colors.blue.shade900,
                    descriptionColor: Colors.blue.shade800,
                    removeCampusPrefix: remove,
                    hideLocation: hide,
                    onTap: () {},
                  ),
                ),
              ),
            ),
          ),
        );
    final location = find.byWidgetPredicate(
      (widget) => widget is Text && widget.semanticsLabel == '地点：$address',
    );
    await pump();
    expect(tester.widget<Text>(location).data, contains('弘远楼A302'));
    expect(tester.widget<Text>(location).data, startsWith('@花溪校区'));
    expect(event.address, address);
    await pump(remove: true);
    expect(tester.widget<Text>(location).data, contains('弘远楼A302'));
    expect(tester.widget<Text>(location).data, isNot(contains('花溪校区')));
    expect(event.address, address);
    await pump(hide: true);
    expect(location, findsNothing);
    expect(tester.takeException(), isNull);
  });

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

    expect(find.text('程序设计'), findsOneWidget);
    expect(find.text('博园201'), findsOneWidget);
    expect(find.text('张老师'), findsNothing);
    expect(tester.widget<Text>(find.text('程序设计')).textAlign, TextAlign.center);
  });

  testWidgets('冲突卡片使用图标文字提示并触发点击回调', (tester) async {
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

    final interaction = find.byKey(
      ScheduleCourseCard.interactionKeyForEvent(event),
    );
    await tester.tap(interaction);
    await tester.pump();
    expect(taps, 1);
  });
  for (final scale in [1.0, 1.6, 2.0]) {
    testWidgets('窄卡在 $scale 倍文字保留名称和地点且不溢出', (tester) async {
      const title = '计算机组成原理与体系结构实验';
      const address = '@第三教学楼超长实验室名称302';
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: scale == 1 ? 52 : 40,
                height: 70,
                child: ScheduleCourseCard(
                  event: EventItem(
                    eventName: title,
                    address: address.substring(1),
                    memberName: '张老师',
                  ),
                  backgroundColor: Colors.blue.shade50,
                  borderColor: Colors.blue,
                  titleColor: Colors.blue.shade900,
                  descriptionColor: Colors.blue.shade800,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text(title), findsOneWidget);
      final location = find.byWidgetPredicate(
        (widget) =>
            widget is Text &&
            widget.semanticsLabel == '地点：${address.substring(1)}',
      );
      expect(location, findsOneWidget);
      expect(tester.widget<Text>(location).data, endsWith('302'));
      expect(find.text('张老师'), findsNothing);
      expect(
        tester.getRect(location).bottom,
        lessThanOrEqualTo(
          tester.getRect(find.byType(ScheduleCourseCard)).bottom,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('短名称释放空间给地点和教师，极短卡只保留名称', (tester) async {
    Future<void> pump(double height) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 90,
              height: height,
              child: ScheduleCourseCard(
                event: EventItem(
                  eventName: '数学',
                  address: 'A101',
                  memberName: '张老师',
                ),
                backgroundColor: Colors.blue.shade50,
                borderColor: Colors.blue,
                titleColor: Colors.blue.shade900,
                descriptionColor: Colors.blue.shade800,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await pump(50);
    expect(find.text('张老师'), findsOneWidget);
    await pump(18);
    expect(find.text('数学'), findsOneWidget);
    expect(find.text('@A101'), findsNothing);
    expect(find.text('张老师'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('2倍文字冲突卡扣除徽标后仍保留地点', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 90,
              height: 76,
              child: ScheduleCourseCard(
                event: EventItem(
                  eventName: '长课程名称实验',
                  address: '教学楼A302',
                  memberName: '张老师',
                ),
                backgroundColor: Colors.blue.shade50,
                borderColor: Colors.blue,
                titleColor: Colors.blue.shade900,
                descriptionColor: Colors.blue.shade800,
                conflictCount: 2,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('冲突 +2'), findsOneWidget);
    final location = find.byWidgetPredicate(
      (widget) => widget is Text && widget.semanticsLabel == '地点：教学楼A302',
    );
    expect(location, findsOneWidget);
    expect(tester.widget<Text>(location).data, endsWith('A302'));
    expect(
      tester.getRect(location).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(ScheduleCourseCard)).bottom),
    );
    expect(
      tester.getRect(find.text('长课程名称实验')).top,
      greaterThan(tester.getRect(find.text('冲突 +2')).top),
    );
    expect(tester.takeException(), isNull);
  });
}
