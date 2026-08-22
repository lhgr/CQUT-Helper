import 'dart:io';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('课表背景启用无缝图片切换', (tester) async {
    final file = File(
      [
        Directory.current.path,
        'lib',
        'assets',
        'Icon.png',
      ].join(Platform.pathSeparator),
    );
    expect(file.existsSync(), isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleBackground(
            settings: ScheduleLayoutSettings(backgroundImagePath: file.path),
          ),
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.gaplessPlayback, isTrue);
    expect(image.key, isA<ValueKey<String>>());
  });

  testWidgets('首帧绘制前背景图片已进入缓存', (tester) async {
    final file = File(
      [
        Directory.current.path,
        'lib',
        'assets',
        'Icon.png',
      ].join(Platform.pathSeparator),
    );
    final provider = FileImage(file);
    await provider.evict();

    await tester.runAsync(() => ScheduleBackground.preloadFile(file.path));

    final status = await provider.obtainCacheStatus(
      configuration: ImageConfiguration.empty,
    );
    expect(status?.keepAlive, isTrue);
  });

  testWidgets('离开课表时背景图片仍保持挂载', (tester) async {
    final file = File(
      [
        Directory.current.path,
        'lib',
        'assets',
        'Icon.png',
      ].join(Platform.pathSeparator),
    );
    final settings = ScheduleLayoutSettings(backgroundImagePath: file.path);

    Widget app({required bool visible}) {
      return MaterialApp(
        home: ScheduleBackgroundLayer(settings: settings, visible: visible),
      );
    }

    await tester.pumpWidget(app(visible: false));
    expect(find.byType(ScheduleBackground), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);

    await tester.pumpWidget(app(visible: true));
    expect(find.byType(ScheduleBackground), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
