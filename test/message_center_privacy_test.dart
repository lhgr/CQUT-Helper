import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/MessageCenter/message_center_page.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final scenario in [
    (name: '未开启调课通知增强时解释变更记录仅来自本地检测', enabled: false),
    (name: '已开启调课通知增强时不展示关闭提示', enabled: true),
  ]) {
    testWidgets(scenario.name, (tester) async {
      SharedPreferences.setMockInitialValues({
        'account': '20260001',
        if (scenario.enabled) ...{
          ScheduleSettingsManager.backgroundPollingEnabledKey: true,
          ScheduleSettingsManager.noticePrivacyConsentVersionKey:
              ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
        },
      });

      await tester.pumpWidget(const MaterialApp(home: MessageCenterPage()));
      await tester.pumpAndSettle();

      final privacyHint = scenario.enabled ? findsNothing : findsOneWidget;
      expect(find.text('调课通知增强未开启'), privacyHint);
      expect(find.text('课表变更记录'), findsOneWidget);
      if (!scenario.enabled) {
        expect(find.textContaining('未开启时不会查询调课通知'), findsOneWidget);
        expect(find.textContaining('本机保存的历史记录'), findsOneWidget);
      }
    });
  }
}
