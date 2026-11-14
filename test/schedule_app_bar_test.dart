import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_app_bar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('普通字号并排入口缩短顶部且背景仅在顶部提供中性衬底', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: ScheduleAppBar(
              context: context,
              availableWidth: constraints.maxWidth,
              loading: false,
              weekList: const ['2'],
              currentWeekIndex: 0,
              currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
              transparentBackground: true,
              onRefresh: () {},
              onSettings: () {},
              onWeekPicker: () {},
              onTermPicker: () {},
            ),
            body: const Text('课程网格'),
          ),
        ),
      ),
    );
    final bar = tester.widget<ScheduleAppBar>(find.byType(ScheduleAppBar));
    expect(bar.preferredSize.height, lessThanOrEqualTo(64));
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, bar.preferredSize.height);
    expect(appBar.backgroundColor?.a, greaterThan(0.9));
    expect(
      tester.getRect(find.text('第2周')).center.dy,
      closeTo(tester.getRect(find.text('2026-2027-1学期')).center.dy, 1),
    );
    for (final label in ['第2周', '2026-2027-1学期']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(TextButton),
      );
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

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
              .copyWith(textScaler: const TextScaler.linear(2), boldText: true),
          child: child!,
        ),
        home: LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: ScheduleAppBar(
              context: context,
              availableWidth: constraints.maxWidth,
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
      ),
    );

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
    final bar = tester.widget<ScheduleAppBar>(find.byType(ScheduleAppBar));
    expect(
      tester.widget<AppBar>(find.byType(AppBar)).toolbarHeight,
      bar.preferredSize.height,
    );
    expect(
      tester.getRect(termButton).bottom,
      lessThanOrEqualTo(tester.getRect(find.byType(AppBar)).bottom),
    );
    expect(find.byTooltip('2026-2027-1学期'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('第1周'));
    await tester.tap(find.text('2026-2027-1学期'));
    expect(weekOpened, isTrue);
    expect(termOpened, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320宽普通字号顶部比旧112高度更紧凑且按钮位于实际边界内', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: ScheduleAppBar(
              context: context,
              availableWidth: constraints.maxWidth,
              loading: false,
              weekList: const ['2'],
              currentWeekIndex: 0,
              currentScheduleData: ScheduleData(yearTerm: '2026-2027-1'),
              onRefresh: () {},
              onSettings: () {},
              onWeekPicker: () {},
              onTermPicker: () {},
            ),
          ),
        ),
      ),
    );
    final bounds = tester.getRect(find.byType(AppBar));
    expect(bounds.height, lessThan(112));
    for (final label in ['第2周', '2026-2027-1学期']) {
      final button = find.ancestor(
        of: find.text(label),
        matching: find.byType(TextButton),
      );
      final rect = tester.getRect(button);
      expect(rect.height, greaterThanOrEqualTo(48));
      expect(rect.width, greaterThanOrEqualTo(48));
      expect(rect.left, greaterThanOrEqualTo(bounds.left));
      expect(rect.right, lessThanOrEqualTo(bounds.right));
      expect(rect.bottom, lessThanOrEqualTo(bounds.bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('刷新按钮下不展示最后更新时间', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: ScheduleAppBar(
              context: context,
              availableWidth: constraints.maxWidth,
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
        home: LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: ScheduleAppBar(
              context: context,
              availableWidth: constraints.maxWidth,
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
      ),
    );

    final refreshTooltip = find.byTooltip('最后更新：今天 23:12更新');
    final refreshFinder = find
        .ancestor(of: refreshTooltip, matching: find.byType(IconButton))
        .first;
    expect(tester.getSize(refreshFinder).width, greaterThanOrEqualTo(48));
    await tester.tap(refreshTooltip);
    expect(refreshCount, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: ScheduleAppBar(
              context: context,
              availableWidth: constraints.maxWidth,
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
        home: LayoutBuilder(
          builder: (context, constraints) => Scaffold(
            appBar: ScheduleAppBar(
              context: context,
              availableWidth: constraints.maxWidth,
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
      ),
    );

    await tester.tap(find.byTooltip('更多课表操作'));
    await tester.pumpAndSettle();
    expect(find.text('课表操作'), findsOneWidget);
    expect(find.text('添加自定义课程'), findsOneWidget);
    expect(find.text('课表设置'), findsOneWidget);

    await tester.tap(find.text('课表设置'));
    await tester.pumpAndSettle();
    expect(settingsOpened, isTrue);
  });
}
