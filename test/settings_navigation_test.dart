import 'dart:io';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/pages/Settings/appearance_startup_settings_page.dart';
import 'package:cqut_helper/pages/Settings/schedule_courses_settings_page.dart';
import 'package:cqut_helper/pages/Settings/schedule_layout_preview.dart';
import 'package:cqut_helper/pages/Settings/settings_schedule_scope.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _openLayoutSettings(WidgetTester tester) async {
  expect(find.text('课表设置'), findsOneWidget);
  expect(find.byType(ScheduleLayoutPreview), findsNothing);
  await tester.tap(
    find.byKey(const ValueKey('schedule-layout-settings-entry')),
  );
  await tester.pumpAndSettle();
  expect(find.text('布局与外观'), findsOneWidget);
  expect(find.byType(ScheduleLayoutPreview), findsOneWidget);
}

Future<void> _ensureSettingsTargetVisible(
  WidgetTester tester,
  Finder target,
) async {
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'account': 'test-user'});
  });

  testWidgets('课表设置总页的五个显示选项切换后即时保存', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('显示周末'));
    await tester.pumpAndSettle();

    final manager = ScheduleSettingsManager();
    await manager.load();
    expect(manager.showWeekend, isTrue);

    await tester.tap(find.text('显示节次时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏上课地点'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('隐藏授课老师'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移除地点前的校区标识'));
    await tester.pumpAndSettle();

    await manager.load();
    expect(manager.timeInfoEnabled, isFalse);
    expect(manager.layoutSettings.hideLocation, isTrue);
    expect(manager.layoutSettings.hideTeacher, isTrue);
    expect(manager.layoutSettings.removeCampusPrefix, isTrue);
  });

  testWidgets('布局子页预览固定在顶部且无背景时隐藏背景调节项', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openLayoutSettings(tester);

    final preview = find.byType(ScheduleLayoutPreview);
    expect(preview, findsOneWidget);
    expect(
      find.ancestor(of: preview, matching: find.byType(ListView)),
      findsNothing,
    );
    expect(find.byType(ListView), findsOneWidget);

    final backgroundSetting = find.text('自定义背景图片');
    await _ensureSettingsTargetVisible(tester, backgroundSetting);
    expect(backgroundSetting, findsOneWidget);
    expect(find.text('背景图片不透明度'), findsNothing);
    expect(find.text('背景模糊度'), findsNothing);
    expect(find.text('从背景图片取色'), findsNothing);
  });

  testWidgets('已选择背景时显示背景与课表局部配色设置', (tester) async {
    final backgroundPath = [
      Directory.current.path,
      'lib',
      'assets',
      'Icon.png',
    ].join(Platform.pathSeparator);
    SharedPreferences.setMockInitialValues({
      'account': 'test-user',
      'schedule_background_image_path': backgroundPath,
      'schedule_background_interface_brightness': 'light',
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openLayoutSettings(tester);

    await _ensureSettingsTargetVisible(tester, find.text('自定义背景图片'));
    expect(find.text('背景图片不透明度'), findsOneWidget);
    expect(find.text('背景模糊度'), findsOneWidget);
    expect(find.text('从背景图片取色'), findsOneWidget);
    expect(find.text('课表配色模式'), findsOneWidget);
    expect(find.textContaining('自动 · 当前：'), findsOneWidget);
    expect(find.text('导航区域背景强度'), findsNothing);
    expect(find.text('高级模式'), findsNothing);

    Finder backgroundOpacitySlider() {
      final setting = find
          .ancestor(of: find.text('背景图片不透明度'), matching: find.byType(Padding))
          .first;
      return find.descendant(of: setting, matching: find.byType(Slider));
    }

    tester.widget<Slider>(backgroundOpacitySlider()).onChanged!(1);
    await tester.pump();
    var previewOverlay = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ScheduleLayoutPreview),
        matching: find.byKey(ScheduleBackground.opacityOverlayKey),
      ),
    );
    expect(previewOverlay.color.a, 1);

    tester.widget<Slider>(backgroundOpacitySlider()).onChanged!(0);
    await tester.pump();
    previewOverlay = tester.widget<ColoredBox>(
      find.descendant(
        of: find.byType(ScheduleLayoutPreview),
        matching: find.byKey(ScheduleBackground.opacityOverlayKey),
      ),
    );
    expect(previewOverlay.color.a, 0);

    final colorModeSetting = find.text('课表配色模式');
    await _ensureSettingsTargetVisible(tester, colorModeSetting);
    await tester.tap(colorModeSetting);
    await tester.pumpAndSettle();
    expect(find.text('自动匹配背景'), findsOneWidget);
    expect(find.text('浅色界面'), findsOneWidget);
    expect(find.text('深色界面'), findsOneWidget);
    expect(find.text('跟随应用'), findsOneWidget);

    await tester.tap(find.text('深色界面'));
    await tester.pumpAndSettle();
    expect(find.text('深色界面'), findsOneWidget);
    expect(
      tester
          .widget<ScheduleLayoutPreview>(find.byType(ScheduleLayoutPreview))
          .settings
          .colorMode,
      ScheduleColorMode.dark,
    );
  });

  testWidgets('课表布局修改未保存时离开会显示提示', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openLayoutSettings(tester);

    final showGridLines = find.text('显示网格线');
    await _ensureSettingsTargetVisible(tester, showGridLines);
    await tester.tap(showGridLines);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.text('修改尚未保存'), findsOneWidget);
    expect(find.text('继续编辑'), findsOneWidget);
    expect(find.text('不保存'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, '保存'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('网格线透明度仅在显示网格线时可调整', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openLayoutSettings(tester);

    final showGridLines = find.text('显示网格线');
    await _ensureSettingsTargetVisible(tester, showGridLines);

    Slider opacitySlider() => tester.widget<Slider>(
      find.byWidgetPredicate(
        (widget) => widget is Slider && widget.value == 0.2,
      ),
    );

    expect(find.text('网格线透明度'), findsOneWidget);
    expect(opacitySlider().onChanged, isNotNull);

    await tester.tap(showGridLines);
    await tester.pumpAndSettle();

    expect(opacitySlider().onChanged, isNull);

    await _ensureSettingsTargetVisible(tester, showGridLines);
    await tester.tap(showGridLines);
    await tester.pumpAndSettle();

    expect(opacitySlider().onChanged, isNotNull);
  });

  testWidgets('布局重置需要二次确认并保留课表显示选项', (tester) async {
    SharedPreferences.setMockInitialValues({
      'account': 'test-user',
      'schedule_grid_cell_width': 72.0,
      'schedule_card_hide_location': true,
      'schedule_card_hide_teacher': true,
      'schedule_card_remove_campus_prefix': true,
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openLayoutSettings(tester);

    expect(
      tester
          .widget<ScheduleLayoutPreview>(find.byType(ScheduleLayoutPreview))
          .settings
          .gridCellWidth,
      72,
    );

    await tester.tap(find.widgetWithText(TextButton, '重置'));
    await tester.pumpAndSettle();
    expect(find.text('重置布局与外观？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<ScheduleLayoutPreview>(find.byType(ScheduleLayoutPreview))
          .settings
          .gridCellWidth,
      72,
    );

    await tester.tap(find.widgetWithText(TextButton, '重置'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '确认重置'));
    await tester.pumpAndSettle();

    expect(find.text('重置布局与外观？'), findsNothing);
    final settings = tester
        .widget<ScheduleLayoutPreview>(find.byType(ScheduleLayoutPreview))
        .settings;
    expect(
      settings.gridCellWidth,
      const ScheduleLayoutSettings().gridCellWidth,
    );
    expect(settings.hideLocation, isTrue);
    expect(settings.hideTeacher, isTrue);
    expect(settings.removeCampusPrefix, isTrue);
  });

  testWidgets('滑杆独立重置按钮直接恢复且不弹确认框', (tester) async {
    SharedPreferences.setMockInitialValues({
      'account': 'test-user',
      'schedule_grid_cell_width': 72.0,
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _openLayoutSettings(tester);

    final resetWidth = find.byTooltip('重置网格宽度');
    expect(resetWidth, findsOneWidget);
    expect(find.byTooltip('重置网格高度'), findsNothing);

    await _ensureSettingsTargetVisible(tester, resetWidth);
    await tester.tap(resetWidth);
    await tester.pumpAndSettle();

    expect(find.text('重置布局与外观？'), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byTooltip('重置网格宽度'), findsNothing);
    expect(
      tester
          .widget<ScheduleLayoutPreview>(find.byType(ScheduleLayoutPreview))
          .settings
          .gridCellWidth,
      const ScheduleLayoutSettings().gridCellWidth,
    );
  });

  testWidgets('长按手动选择颜色会解锁并应用 Wing', (tester) async {
    await ThemeManager().init();
    await tester.pumpWidget(
      const MaterialApp(home: AppearanceStartupSettingsPage()),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.text('手动选择颜色'));
    await tester.pumpAndSettle();

    expect(find.text('Wing 已解锁 · #FF98A1'), findsOneWidget);
    expect(find.byTooltip('Wing · #FF98A1'), findsOneWidget);
    expect(ThemeManager().wingColorUnlocked, isTrue);
    expect(ThemeManager().customColor, ThemeManager.wingColor);
    expect(ThemeManager().colorSource, ThemeColorSource.custom);
  });

  testWidgets('预测性返回手势可在外观设置中关闭', (tester) async {
    await ThemeManager().init();
    await tester.pumpWidget(
      const MaterialApp(home: AppearanceStartupSettingsPage()),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -900));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭预测性返回手势'));
    await tester.pumpAndSettle();

    expect(ThemeManager().predictiveBackDisabled, isTrue);
  });
}
