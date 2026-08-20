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
}
