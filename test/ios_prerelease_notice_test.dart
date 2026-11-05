import 'package:cqut_helper/manager/app_backup_service.dart';
import 'package:cqut_helper/manager/schedule_update_intents.dart';
import 'package:cqut_helper/pages/Main/Main.dart';
import 'package:cqut_helper/utils/ios_release.dart';
import 'package:cqut_helper/widgets/ios_prerelease_notice.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> openNotice(
    WidgetTester tester, {
    IosReleaseInfo release = currentIosRelease,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () =>
                  showIosPrereleaseNotice(context, release: release),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('确认前无法通过遮罩或系统返回跳过，双击只关闭提示且确认持久化', (tester) async {
    await openNotice(tester);
    expect(find.text('Alpha 测试版本'), findsOneWidget);
    expect(
      find.text('当前为 iOS Alpha 测试版本，部分功能可能尚不完善，使用过程中可能出现异常。'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(5, 5));
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Alpha 测试版本'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(iosPrereleaseNoticeAcknowledgedKey), isNull);

    final confirm = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '我知道了'),
    );
    confirm.onPressed!();
    confirm.onPressed!();
    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(prefs.getBool(iosPrereleaseNoticeAcknowledgedKey), isTrue);
    expect(
      AppBackupService.collectSettingsForTesting(prefs, 'test-user'),
      isNot(contains(iosPrereleaseNoticeAcknowledgedKey)),
    );

    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    await openNotice(
      tester,
      release: const IosReleaseInfo(IosReleaseStage.beta),
    );
    expect(find.byType(AlertDialog), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
    '稳定 iOS 与其他平台跳过提示',
    (tester) async {
      await openNotice(
        tester,
        release: const IosReleaseInfo(IosReleaseStage.stable),
      );
      expect(find.byType(AlertDialog), findsNothing);
      if (defaultTargetPlatform != TargetPlatform.iOS) {
        await openNotice(tester);
        expect(find.byType(AlertDialog), findsNothing);
      }
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey(iosPrereleaseNoticeAcknowledgedKey), isFalse);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );

  testWidgets('Beta 首次提示使用当前阶段', (tester) async {
    await openNotice(
      tester,
      release: const IosReleaseInfo(IosReleaseStage.beta),
    );
    expect(find.text('Beta 测试版本'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  for (final hasAccount in [false, true]) {
    testWidgets('首页先完成提示再检查登录（已有账号 $hasAccount）', (tester) async {
      SharedPreferences.setMockInitialValues({
        if (hasAccount) 'account': 'test-user',
      });
      final previousOpenToken = ScheduleUpdateIntents.openChangesSheet.value;
      await tester.pumpWidget(
        MaterialApp(
          home: const MainPage(),
          routes: {'/login': (_) => const Scaffold(body: Text('登录入口'))},
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Alpha 测试版本'), findsOneWidget);
      expect(find.text('登录入口'), findsNothing);
      expect(find.byType(NavigationBar), findsNothing);

      ScheduleUpdateIntents.requestOpenFromNotification();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(ScheduleUpdateIntents.openChangesSheet.value, previousOpenToken);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('account');
      await tester.tap(find.text('我知道了'));
      await tester.pumpAndSettle();
      expect(find.text('登录入口'), findsOneWidget);
      expect(find.text('Alpha 测试版本'), findsNothing);
    }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
  }

  testWidgets('已有账号确认后进入首页，重新启动沿用确认记录', (tester) async {
    SharedPreferences.setMockInitialValues({
      'account': 'test-user',
      'schedule_default_home_tab': 2,
      'user_info_test-user': '{}',
    });
    PackageInfo.setMockInitialValues(
      appName: 'CQUT Helper',
      packageName: 'top.dawndrizzle.cqut',
      version: '1.2.1',
      buildNumber: '2015',
      buildSignature: '',
    );
    await tester.pumpWidget(const MaterialApp(home: MainPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Alpha 测试版本'), findsOneWidget);
    await tester.tap(find.text('我知道了'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    final previousOpenToken = ScheduleUpdateIntents.openChangesSheet.value;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(const MaterialApp(home: MainPage()));
    await tester.pumpAndSettle();
    expect(find.text('Alpha 测试版本'), findsNothing);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(ScheduleUpdateIntents.openChangesSheet.value, previousOpenToken);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
