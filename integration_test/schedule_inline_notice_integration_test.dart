import 'package:cqut/pages/ClassSchedule/widgets/schedule_inline_notice_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('不同屏幕尺寸下通知可见且可关闭', (tester) async {
    final sizes = <Size>[
      const Size(360, 780),
      const Size(768, 1024),
      const Size(1024, 1366),
    ];
    final notices = <String>[
      '第5周星期四第9-10节的**深度学习**课程调课到第16周星期四第1-2节',
      '第7周星期一第3-4节的**高等数学**课程调课到第8周星期三第7-8节',
    ];
    int dismissCount = 0;

    for (final size in sizes) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ScheduleInlineNoticePanel(
              notices: notices,
              onDismissOne: (_) {
                dismissCount += 1;
              },
              onDismissAll: () {
                dismissCount += 10;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('调课通知'), findsOneWidget);
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      expect(
        richTexts.any((r) => r.text.toPlainText().contains('深度学习')),
        true,
      );
      expect(find.byIcon(Icons.close), findsNWidgets(2));
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pump();
    }

    expect(dismissCount, 3);
    await tester.tap(find.text('知道了'));
    await tester.pump();
    expect(dismissCount, 13);
    await tester.binding.setSurfaceSize(null);
  });
}
