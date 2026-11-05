import 'package:cqut_helper/pages/Settings/about_settings_page.dart';
import 'package:flutter/foundation.dart';
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
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.android,
    }),
  );
}
