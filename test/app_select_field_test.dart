import 'package:cqut_helper/widgets/app_select_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('选择字段使用底部选项页并返回选中值', (tester) async {
    var value = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelectField<int>(
            value: value,
            labelText: '启动后的默认页面',
            sheetTitle: '选择默认页面',
            options: const [
              AppSelectOption(value: 0, label: '今日'),
              AppSelectOption(value: 1, label: '课表'),
              AppSelectOption(value: 2, label: '我的'),
            ],
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    await tester.tap(find.text('课表'));
    await tester.pumpAndSettle();
    expect(find.text('选择默认页面'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);

    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(value, 2);
    expect(find.text('选择默认页面'), findsNothing);
  });

  testWidgets('可选择值为 null 的跟随全局选项', (tester) async {
    int? value = 10;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppSelectField<int?>(
            value: value,
            labelText: '课前提醒',
            options: const [
              AppSelectOption(value: null, label: '跟随全局设置'),
              AppSelectOption(value: 10, label: '提前 10 分钟'),
            ],
            onChanged: (next) => value = next,
          ),
        ),
      ),
    );

    await tester.tap(find.text('提前 10 分钟'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('跟随全局设置'));
    await tester.pumpAndSettle();
    expect(value, isNull);
  });
}
