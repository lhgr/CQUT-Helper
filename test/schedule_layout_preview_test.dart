import 'dart:io';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/pages/Settings/schedule_layout_preview.dart';
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

  testWidgets('背景预览从图片顶部裁剪，并让顶栏与侧栏透明', (tester) async {
    final file = existingImage();
    expect(file.existsSync(), isTrue);

    await tester.pumpWidget(
      preview(ScheduleLayoutSettings(backgroundImagePath: file.path)),
    );

    final image = tester.widget<Image>(find.byType(Image));
    expect(image.fit, BoxFit.cover);
    expect(image.alignment, ScheduleBackground.imageAlignment);

    final header = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-header')),
    );
    final timeColumn = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-time-column')),
    );
    expect(header.color, Colors.transparent);
    expect(timeColumn.color, Colors.transparent);
  });

  testWidgets('没有可用背景图片时预览顶栏与侧栏保持实色', (tester) async {
    await tester.pumpWidget(preview(const ScheduleLayoutSettings()));

    final header = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-header')),
    );
    final timeColumn = tester.widget<Container>(
      find.byKey(const ValueKey('schedule-layout-preview-time-column')),
    );
    expect(header.color, isNot(Colors.transparent));
    expect(timeColumn.color, isNot(Colors.transparent));
  });
}
