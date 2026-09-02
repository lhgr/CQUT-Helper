import 'package:cqut_helper/widgets/marquee_text.dart';
import 'package:flutter/material.dart';
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
}
