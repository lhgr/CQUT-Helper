import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_inline_notice_panel.dart';
import 'package:cqut_helper/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  final List<String> initial;
  const _Host({super.key, required this.initial});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late List<String> notices = List.of(widget.initial);
  final dismissed = <int>[];
  int dismissedAll = 0;
  void replace(List<String> value) => setState(() => notices = value);
  @override
  Widget build(BuildContext context) => Scaffold(
    body: notices.isEmpty
        ? const SizedBox.shrink()
        : ScheduleInlineNoticePanel(
            notices: notices,
            onDismissOne: (index) {
              dismissed.add(index);
              setState(() => notices = List.of(notices)..removeAt(index));
            },
            onDismissAll: () {
              dismissedAll++;
              setState(() => notices = []);
            },
          ),
  );
}

Future<GlobalKey<_HostState>> _pump(
  WidgetTester tester,
  List<String> notices, {
  double scale = 1,
}) async {
  final key = GlobalKey<_HostState>();
  tester.view.physicalSize = const Size(320, 640);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(ColorScheme.fromSeed(seedColor: Colors.teal)),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: _Host(key: key, initial: notices),
    ),
  );
  return key;
}

void main() {
  testWidgets('汇总保持紧凑，查看详情不关闭通知并保留粗体', (tester) async {
    final key = await _pump(tester, ['**高等数学**调课到周三', '操作系统调课到周四']);
    expect(find.text('2条调课通知'), findsOneWidget);
    expect(find.textContaining('高等数学', findRichText: true), findsNothing);
    final ink = find.descendant(
      of: find.byType(ScheduleInlineNoticePanel),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(ink).height, inInclusiveRange(48, 64));
    await tester.tap(
      find.byKey(const ValueKey('schedule-inline-notice-summary')),
    );
    await tester.pumpAndSettle();
    expect(key.currentState!.dismissed, isEmpty);
    expect(key.currentState!.dismissedAll, 0);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .firstWhere((text) => text.textSpan?.toPlainText() == '高等数学调课到周三');
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.text, '高等数学');
    expect(spans.first.style!.fontWeight, FontWeight.w700);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('2条调课通知'), findsOneWidget);
  });

  testWidgets('逐条关闭使用当前索引，知道了只关闭全部剩余通知', (tester) async {
    final key = await _pump(tester, ['第一条', '第二条', '第三条']);
    await tester.tap(
      find.byKey(const ValueKey('schedule-inline-notice-summary')),
    );
    await tester.pumpAndSettle();
    final close = tester
        .widget<IconButton>(
          find
              .byWidgetPredicate(
                (widget) => widget is IconButton && widget.tooltip == '关闭此通知',
              )
              .at(1),
        )
        .onPressed!;
    close();
    close();
    await tester.pumpAndSettle();
    expect(find.text('第二条', findRichText: true), findsNothing);
    expect(key.currentState!.dismissed, [1]);
    expect(key.currentState!.notices, ['第一条', '第三条']);
    await tester.tap(find.byTooltip('关闭此通知').at(1));
    await tester.pumpAndSettle();
    expect(key.currentState!.dismissed, [1, 1]);
    expect(key.currentState!.notices, ['第一条']);
    final closeAll = tester
        .widget<TextButton>(find.widgetWithText(TextButton, '知道了'))
        .onPressed!;
    closeAll();
    closeAll();
    await tester.pumpAndSettle();
    expect(key.currentState!.dismissedAll, 1);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(ScheduleInlineNoticePanel), findsNothing);
  });

  testWidgets('父通知替换后详情跟随更新，清空后关闭面板', (tester) async {
    final key = await _pump(tester, ['旧通知', '另一条旧通知']);
    await tester.tap(
      find.byKey(const ValueKey('schedule-inline-notice-summary')),
    );
    await tester.pumpAndSettle();
    key.currentState!.replace(['新通知A', '新通知B']);
    await tester.pumpAndSettle();
    expect(find.text('旧通知', findRichText: true), findsNothing);
    expect(find.text('新通知A', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('关闭此通知').first);
    await tester.pumpAndSettle();
    expect(key.currentState!.notices, ['新通知B']);
    expect(key.currentState!.dismissed, [0]);
    key.currentState!.replace([]);
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('最后一条关闭时退出详情，320与2倍文字可滚动无溢出', (tester) async {
    final key = await _pump(tester, [
      List.filled(30, '**数字图像处理**调课到第三教学楼302。').join(),
    ], scale: 2);
    await tester.tap(
      find.byKey(const ValueKey('schedule-inline-notice-summary')),
    );
    await tester.pumpAndSettle();
    expect(find.text('知道了').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.drag(find.byType(ListView), const Offset(0, 5000));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭此通知'));
    await tester.pumpAndSettle();
    expect(key.currentState!.dismissed, [0]);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
