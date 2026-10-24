import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('窄屏大字下周次和学期入口保留48高触控区域', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var weekOpened = false;
    var termOpened = false;

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          appBar: ScheduleAppBar(
            loading: false,
            weekList: const ['1'],
            currentWeekIndex: 0,
            currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
            onRefresh: () {},
            onSettings: () {},
            onWeekPicker: () => weekOpened = true,
            onTermPicker: () => termOpened = true,
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(AppBar)).height, 112);
    final weekButton = find.ancestor(
      of: find.text('第1周'),
      matching: find.byType(TextButton),
    );
    final termButton = find.ancestor(
      of: find.text('2026-2027-1学期'),
      matching: find.byType(TextButton),
    );
    expect(tester.getSize(weekButton).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(termButton).height, greaterThanOrEqualTo(48));
    expect(tester.getCenter(weekButton).dx, closeTo(160, 0.5));
    expect(tester.getCenter(termButton).dx, closeTo(160, 0.5));
    expect(find.byTooltip('2026-2027-1学期'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('第1周'));
    await tester.tap(find.text('2026-2027-1学期'));
    expect(weekOpened, isTrue);
    expect(termOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('背景图下顶栏保持透明', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ScheduleAppBar(
            loading: false,
            weekList: const ['1'],
            currentWeekIndex: 0,
            currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
            onRefresh: () {},
            onSettings: () {},
            onWeekPicker: () {},
            onTermPicker: () {},
            transparentBackground: true,
          ),
        ),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.backgroundColor, Colors.transparent);
  });

  testWidgets('刷新按钮下不展示最后更新时间', (tester) async {
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
          ),
        ),
      ),
    );

    expect(find.text('第2周'), findsOneWidget);
    expect(find.text('2026-2027-1学期'), findsOneWidget);
    expect(find.text('23:12'), findsNothing);
    expect(find.byTooltip('最后更新：今天 23:12更新'), findsOneWidget);
    expect(find.textContaining('2026-2027-1学期 ·'), findsNothing);
  });

  testWidgets('刷新按钮使用无底色普通变体并保留加载与禁用状态', (tester) async {
    var refreshCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ScheduleAppBar(
            loading: false,
            weekList: const ['1'],
            currentWeekIndex: 0,
            currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
            refreshStatusText: '今天 23:12更新',
            onRefresh: () => refreshCount++,
            onSettings: () {},
            onWeekPicker: () {},
            onTermPicker: () {},
          ),
        ),
      ),
    );

    final refreshTooltip = find.byTooltip('最后更新：今天 23:12更新');
    final refreshFinder = find
        .ancestor(of: refreshTooltip, matching: find.byType(IconButton))
        .first;
    final refreshButton = tester.widget<IconButton>(refreshFinder);
    expect(refreshButton.style?.backgroundColor, isNull);
    expect(tester.getSize(refreshFinder).width, greaterThanOrEqualTo(48));
    await tester.tap(refreshTooltip);
    expect(refreshCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ScheduleAppBar(
            loading: true,
            weekList: const ['1'],
            currentWeekIndex: 0,
            currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
            onRefresh: () => refreshCount++,
            onSettings: () {},
            onWeekPicker: () {},
            onTermPicker: () {},
          ),
        ),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final disabledRefresh = find
        .ancestor(of: find.byTooltip('刷新课表'), matching: find.byType(IconButton))
        .first;
    expect(tester.widget<IconButton>(disabledRefresh).onPressed, isNull);
    await tester.tap(find.byTooltip('刷新课表'), warnIfMissed: false);
    expect(refreshCount, 1);
  });

  testWidgets('不再显示独立课程管理入口', (tester) async {
    var settingsOpened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          appBar: ScheduleAppBar(
            loading: false,
            weekList: const ['1'],
            currentWeekIndex: 0,
            currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
            onRefresh: () {},
            onSettings: () => settingsOpened = true,
            onWeekPicker: () {},
            onTermPicker: () {},
          ),
        ),
      ),
    );

    expect(find.text('本学期课程'), findsNothing);
    await tester.tap(find.byTooltip('更多课表操作'));
    await tester.pumpAndSettle();
    expect(find.text('课表操作'), findsOneWidget);
    expect(find.text('添加自定义课程'), findsOneWidget);
    expect(find.text('管理自定义课程'), findsNothing);
    expect(find.text('课表设置'), findsOneWidget);

    await tester.tap(find.text('课表设置'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
  });
}
