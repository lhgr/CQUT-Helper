import 'dart:io';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  File existingImage() => File(
    [
      Directory.current.path,
      'lib',
      'assets',
      'Icon.png',
    ].join(Platform.pathSeparator),
  );

  testWidgets('背景图片始终完整绘制并由新值控制表面覆盖层', (tester) async {
    final file = existingImage();
    const savedOpacity = 0.73;

    await tester.pumpWidget(
      MaterialApp(
        home: ScheduleBackground(
          settings: ScheduleLayoutSettings(
            backgroundImagePath: file.path,
            backgroundOpacity: savedOpacity,
          ),
        ),
      ),
    );

    expect(find.byType(Opacity), findsNothing);
    final overlay = tester.widget<ColoredBox>(
      find.byKey(ScheduleBackground.opacityOverlayKey),
    );
    expect(overlay.color.a, closeTo(savedOpacity, 0.0001));
  });

  testWidgets('首帧绘制前背景图片已进入缓存', (tester) async {
    final file = existingImage();
    final provider = FileImage(file);
    await provider.evict();

    await tester.runAsync(() => ScheduleBackground.preloadFile(file.path));

    final status = await provider.obtainCacheStatus(
      configuration: ImageConfiguration.empty,
    );
    expect(status?.keepAlive, isTrue);
  });

  testWidgets('离开课表时背景图片仍保持挂载', (tester) async {
    final file = existingImage();
    final settings = ScheduleLayoutSettings(backgroundImagePath: file.path);

    Widget app({required bool visible}) {
      return MaterialApp(
        home: ScheduleBackgroundLayer(settings: settings, visible: visible),
      );
    }

    await tester.pumpWidget(app(visible: false));
    final imageElement = tester.element(find.byType(Image));

    await tester.pumpWidget(app(visible: true));
    expect(tester.element(find.byType(Image)), same(imageElement));

    await tester.pumpWidget(app(visible: false));
    expect(tester.element(find.byType(Image)), same(imageElement));
  });
}
