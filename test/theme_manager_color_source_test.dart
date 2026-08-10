import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('removing the timetable background switches to system colors', () async {
    SharedPreferences.setMockInitialValues({
      ScheduleSettingsManager.backgroundImagePathKey: 'background.jpg',
    });
    final manager = ThemeManager();
    await manager.init();

    await manager.applyScheduleBackgroundColor(Colors.deepPurple);
    expect(manager.colorSource, ThemeColorSource.scheduleBackground);
    expect(manager.canUseScheduleBackgroundColor, isTrue);

    await manager.clearScheduleBackgroundColor();

    expect(manager.colorSource, ThemeColorSource.system);
    expect(manager.scheduleBackgroundColor, isNull);
    expect(manager.canUseScheduleBackgroundColor, isFalse);
  });

  test('a missing background repairs a stale extracted-color source', () async {
    SharedPreferences.setMockInitialValues({
      'theme_color_source': ThemeColorSource.scheduleBackground.name,
      'schedule_background_theme_color': Colors.orange.toARGB32(),
    });
    final manager = ThemeManager();

    await manager.init();

    expect(manager.colorSource, ThemeColorSource.system);
    expect(manager.scheduleBackgroundColor, isNull);
    expect(manager.canUseScheduleBackgroundColor, isFalse);
  });

  test('Wing color unlock is persisted', () async {
    SharedPreferences.setMockInitialValues({});
    final manager = ThemeManager();
    await manager.init();
    expect(manager.wingColorUnlocked, isFalse);

    expect(await manager.unlockWingColor(), isTrue);
    await manager.setCustomColor(ThemeManager.wingColor);

    expect(manager.wingColorUnlocked, isTrue);
    expect(manager.customColor, const Color(0xFFFF98A1));
    expect(manager.colorSource, ThemeColorSource.custom);

    await manager.init();
    expect(manager.wingColorUnlocked, isTrue);
    expect(manager.customColor, ThemeManager.wingColor);
  });
}
