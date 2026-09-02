import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/Settings/sync_diagnostics_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<void> pumpPage(
    WidgetTester tester, {
    Future<String?> Function()? readEncryptedPassword,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SyncDiagnosticsPage(readEncryptedPassword: readEncryptedPassword),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('未完整启用调课通知增强时隐藏后台诊断与自启动入口', (tester) async {
    SharedPreferences.setMockInitialValues({
      ScheduleSettingsManager.backgroundPollingEnabledKey: true,
      ScheduleSettingsManager.noticePrivacyConsentVersionKey: 0,
    });

    await pumpPage(tester);

    expect(find.text('通知'), findsOneWidget);
    expect(find.textContaining('后台定时轮询'), findsNothing);
    expect(find.text('后台运行限制'), findsNothing);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('打开自启动设置'), findsNothing);
  });

  testWidgets('启用调课通知增强后显示后台诊断与自启动入口', (tester) async {
    SharedPreferences.setMockInitialValues({
      ScheduleSettingsManager.backgroundPollingEnabledKey: true,
      ScheduleSettingsManager.noticePrivacyConsentVersionKey:
          ScheduleSettingsManager.currentNoticePrivacyConsentVersion,
    });

    await pumpPage(tester);

    expect(find.text('通知与后台'), findsOneWidget);
    expect(find.textContaining('后台定时轮询'), findsWidgets);
    expect(find.text('后台运行限制'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(find.text('打开自启动设置'), findsOneWidget);
  });

  testWidgets('本地账号与凭据完整时不展示重新验证登录', (tester) async {
    SharedPreferences.setMockInitialValues({'account': '20260001'});

    await pumpPage(
      tester,
      readEncryptedPassword: () async => 'encrypted-password',
    );

    expect(find.text('账号与登录凭据已保存；有效性会在同步时验证'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('重新验证登录'), findsNothing);
  });

  testWidgets('最近同步确认凭据失效时才展示重新验证入口', (tester) async {
    SharedPreferences.setMockInitialValues({
      'account': '20260001',
      'schedule_widget_refresh_state_20260001': 'failed',
      'schedule_widget_refresh_failure_20260001': 'credentialInvalid',
    });

    await pumpPage(
      tester,
      readEncryptedPassword: () async => 'encrypted-password',
    );

    expect(find.text('最近一次同步判断登录凭据已失效'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pumpAndSettle();
    expect(find.text('重新验证登录'), findsOneWidget);
  });
}
