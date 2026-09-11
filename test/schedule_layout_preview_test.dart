import 'dart:io';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_card.dart';
import 'package:cqut_helper/pages/Settings/schedule_layout_preview.dart';
import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:flutter/material.dart';
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

  Widget preview(ScheduleLayoutSettings settings) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 310,
          child: ScheduleLayoutPreview(
            settings: settings,
            showWeekend: false,
            timeInfoEnabled: true,
          ),
        ),
      ),
    );
  }

  testWidgets('背景预览从图片顶部裁剪，关键区域保持透明', (tester) async {
    final file = existingImage();
    expect(file.existsSync(), isTrue);

    await tester.pumpWidget(
      preview(
        ScheduleLayoutSettings(
          backgroundImagePath: file.path,
          colorMode: ScheduleColorMode.auto,
          analyzedBackgroundBrightness: Brightness.dark,
        ),
      ),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, ScheduleBackground.imageAlignment);

    final headerFinder = find.byKey(
      const ValueKey('schedule-layout-preview-header'),
    );
    final header = tester.widget<Container>(headerFinder);
    final timeColumn = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-time-column')),
    );
    final bottomBar = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-bottom-bar')),
    );
    expect(header.color, Colors.transparent);
    expect(timeColumn.color, Colors.transparent);
    expect((bottomBar.decoration! as BoxDecoration).color, Colors.transparent);
    expect(Theme.of(tester.element(headerFinder)).brightness, Brightness.dark);
    final firstCourseCard = tester.widget<ScheduleCourseCard>(
      find.byType(ScheduleCourseCard).first,
    );
    expect(
      firstCourseCard.backgroundColor,
      ScheduleCourseCardTheme.light().backgroundAt(0),
    );
  });

  testWidgets('手动配色可覆盖自动分析结果', (tester) async {
    final file = existingImage();
    await tester.pumpWidget(
      preview(
        ScheduleLayoutSettings(
          backgroundImagePath: file.path,
          colorMode: ScheduleColorMode.light,
          analyzedBackgroundBrightness: Brightness.dark,
        ),
      ),
    );

    final headerContext = tester.element(
      find.byKey(const ValueKey('schedule-layout-preview-header')),
    );
    expect(Theme.of(headerContext).brightness, Brightness.light);
  });

  testWidgets('没有可用背景图片时预览保持应用配色和实色表面', (tester) async {
    await tester.pumpWidget(
      preview(const ScheduleLayoutSettings(colorMode: ScheduleColorMode.dark)),
    );

    final headerFinder = find.byKey(
      const ValueKey('schedule-layout-preview-header'),
    );
    final header = tester.widget<Container>(headerFinder);
    final timeColumn = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-time-column')),
    );
    final bottomBar = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-bottom-bar')),
    );
    expect(header.color, isNot(Colors.transparent));
    expect(timeColumn.color, isNot(Colors.transparent));
    expect((bottomBar.decoration! as BoxDecoration).color!.a, 1);
    expect(Theme.of(tester.element(headerFinder)).brightness, Brightness.light);
  });
}
