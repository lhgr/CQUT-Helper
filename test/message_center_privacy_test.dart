import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/MessageCenter/message_center_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('未开启调课通知增强时解释变更记录仅来自本地检测', (tester) async {
    SharedPreferences.setMockInitialValues({'account': '20260001'});

    await tester.pumpWidget(const MaterialApp(home: MessageCenterPage()));
    await tester.pumpAndSettle();

    expect(find.text('调课通知增强未开启'), findsOneWidget);
    expect(find.text('课表变更记录（仅本地）'), findsOneWidget);
    expect(find.textContaining('不会访问官方或第三方调课通知接口'), findsOneWidget);
  });

  testWidgets('已开启调课通知增强时不展示关闭提示', (tester) async {
    SharedPreferences.setMockInitialValues({
      'account': '20260001',
      ScheduleSettingsManager.backgroundPollingEnabledKey: true,
      ScheduleSettingsManager.noticePrivacyConsentVersionKey:
          ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
    });

    await tester.pumpWidget(const MaterialApp(home: MessageCenterPage()));
    await tester.pumpAndSettle();

    expect(find.text('调课通知增强未开启'), findsNothing);
    expect(find.text('课表变更记录'), findsOneWidget);
  });
}
