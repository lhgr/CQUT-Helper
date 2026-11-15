import 'package:cqut_helper/pages/Settings/about_settings_page.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

void main() {
  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'CQUT Helper',
      packageName: 'top.dawndrizzle.cqut',
      version: '1.2.1',
      buildNumber: '2015',
      buildSignature: '',
    );
  });

  testWidgets(
    '关于设置与我的关于弹窗一致显示 iOS 阶段',
    (tester) async {
      final version = defaultTargetPlatform == TargetPlatform.iOS
          ? '1.2.1-alpha'
          : '1.2.1';
      await tester.pumpWidget(const MaterialApp(home: AboutSettingsPage()));
      await tester.pumpAndSettle();
      expect(find.text('版本 $version'), findsOneWidget);
      await tester.tap(find.text('项目与开源'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<AboutDialog>(find.byType(AboutDialog)).applicationVersion,
        version,
      );
      expect(find.text(version), findsOneWidget);
      final launches = <String>[];
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'launch') {
          launches.add((call.arguments as Map)['url'] as String);
          return true;
        }
        return true;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
      });
      for (final tooltip in ['GitHub', '发送邮件']) {
        final button = find.byTooltip(tooltip);
        expect(button, findsOneWidget);
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }
      expect(launches, [
        'https://github.com/lhgr/CQUT-Helper',
        'mailto:dawndrizzle0104@gamil.com',
      ]);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
