import 'package:cqut_helper/widgets/marquee_text.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('长文本溢出时自动横向滚动', (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 90,
            child: MarqueeText(
              '留空使用官方服务；检查时会使用当前登录凭据实际查询调课信息',
              pause: Duration(milliseconds: 10),
              pixelsPerSecond: 200,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200));

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scrollView.controller!.offset, greaterThan(0));
    expect(find.textContaining('留空使用官方服务'), findsOneWidget);
  });
  for (final preference in ['disableAnimations', 'accessibleNavigation']) {
    testWidgets('$preference变化时停止动画并完整换行，关闭后恢复滚动', (tester) async {
      var staticText = false;
      late StateSetter update;
      const text = '留空使用官方服务；检查时会使用当前登录凭据实际查询调课信息';
      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  disableAnimations:
                      preference == 'disableAnimations' && staticText,
                  accessibleNavigation:
                      preference == 'accessibleNavigation' && staticText,
                ),
                child: const Scaffold(
                  body: SizedBox(
                    width: 90,
                    child: MarqueeText(
                      text,
                      pause: Duration(milliseconds: 10),
                      pixelsPerSecond: 200,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 200));
      final initialScroll = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(initialScroll.controller!.offset, greaterThan(0));
      update(() => staticText = true);
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(SingleChildScrollView), findsNothing);
      final wrapped = tester.widget<Text>(find.text(text));
      expect(wrapped.maxLines, isNull);
      expect(wrapped.softWrap, isTrue);
      expect(tester.getSize(find.text(text)).height, greaterThan(40));
      expect(tester.binding.transientCallbackCount, 0);
      update(() => staticText = false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump(const Duration(milliseconds: 200));
      final resumed = tester.widget<SingleChildScrollView>(
        find.byType(SingleChildScrollView),
      );
      expect(resumed.controller!.offset, greaterThan(0));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('减少动画时InputDecoration辅助说明显示全文而非单行裁切', (tester) async {
    const text = '仅支持 HTTPS；检查时会使用当前登录凭据实际查询，失败时不会回退其他服务';
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: SizedBox(
            width: 180,
            child: TextField(
              decoration: InputDecoration(helper: MarqueeText(text)),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.widget<Text>(find.text(text)).maxLines, isNull);
    expect(tester.getSize(find.text(text)).height, greaterThan(30));
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('同一文本从不溢出变窄或放大字体后重新开始滚动', (tester) async {
    var width = 600.0;
    var scale = 1.0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: Scaffold(
                body: SizedBox(
                  width: width,
                  child: const MarqueeText(
                    '留空使用官方服务；检查时会使用当前登录凭据实际查询调课信息',
                    pause: Duration(milliseconds: 10),
                    pixelsPerSecond: 200,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    ScrollController controller() => tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .controller!;
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller().position.maxScrollExtent, 0);
    update(() => width = 90);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller().offset, greaterThan(0));
    update(() => width = 600);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    expect(controller().position.maxScrollExtent, 0);
    update(() => scale = 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    await tester.pump(const Duration(milliseconds: 200));
    expect(controller().offset, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
