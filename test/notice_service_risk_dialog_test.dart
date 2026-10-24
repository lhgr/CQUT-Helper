import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/widgets/notice_service_risk_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('确认自定义服务风险后可选择不再提示', (tester) async {
    SharedPreferences.setMockInitialValues({});
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await confirmCustomNoticeServiceRisk(context);
              },
              child: const Text('保存自定义地址'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('保存自定义地址'));
    await tester.pumpAndSettle();
    expect(find.text('使用自定义调课服务'), findsOneWidget);

    await tester.tap(find.text('以后不再提示'));
    await tester.tap(find.text('我已了解，继续'));
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(
      await ScheduleSettingsManager.shouldShowCustomServiceRiskWarning(),
      isFalse,
    );
  });
}
