import 'package:cqut_helper/theme/schedule_grid_line_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('网格线从当前动态配色取色并应用透明度', (tester) async {
    const dynamicOutline = Color(0xff2468ac);
    late Color resolved;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.orange,
          ).copyWith(outlineVariant: dynamicOutline),
        ),
        home: Builder(
          builder: (context) {
            resolved = scheduleGridLineColor(context, 0.4);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(resolved, dynamicOutline.withAlpha(102));
  });
}
