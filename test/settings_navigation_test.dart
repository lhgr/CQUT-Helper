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

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'account': 'test-user'});
  });

  testWidgets('课表显示选项切换后即时保存', (tester) async {
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
  });

  testWidgets('课表预览固定在顶部且无背景时隐藏背景调节项', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final preview = find.byType(ScheduleLayoutPreview);
    expect(preview, findsOneWidget);
    expect(
      find.ancestor(of: preview, matching: find.byType(ListView)),
      findsNothing,
    );
    expect(find.byType(ListView), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('自定义背景图片'), findsOneWidget);
    expect(find.text('背景图片不透明度'), findsNothing);
    expect(find.text('背景模糊度'), findsNothing);
    expect(find.text('从背景图片取色'), findsNothing);
  });

  testWidgets('已选择背景时显示不透明度和模糊度设置', (tester) async {
    final backgroundPath = [
      Directory.current.path,
      'lib',
      'assets',
      'Icon.png',
    ].join(Platform.pathSeparator);
    SharedPreferences.setMockInitialValues({
      'account': 'test-user',
      'schedule_background_image_path': backgroundPath,
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('背景图片不透明度'), findsOneWidget);
    expect(find.text('背景模糊度'), findsOneWidget);
    expect(find.text('从背景图片取色'), findsOneWidget);

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

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    await tester.tap(find.text('显示网格线'));
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

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    Slider opacitySlider() => tester.widget<Slider>(
      find.byWidgetPredicate(
        (widget) => widget is Slider && widget.value == 0.2,
      ),
    );

    expect(find.text('网格线透明度'), findsOneWidget);
    expect(opacitySlider().onChanged, isNotNull);

    await tester.tap(find.text('显示网格线'));
    await tester.pumpAndSettle();

    expect(opacitySlider().onChanged, isNull);

    await tester.tap(find.text('显示网格线'));
    await tester.pumpAndSettle();

    expect(opacitySlider().onChanged, isNotNull);
  });

  testWidgets('顶部重置需要二次确认', (tester) async {
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

    expect(
      tester
          .widget<ScheduleLayoutPreview>(find.byType(ScheduleLayoutPreview))
          .settings
          .gridCellWidth,
      72,
    );

    await tester.tap(find.widgetWithText(TextButton, '重置'));
    await tester.pumpAndSettle();
    expect(find.text('重置课表设置？'), findsOneWidget);

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

    expect(find.text('重置课表设置？'), findsNothing);
    expect(
      tester
          .widget<ScheduleLayoutPreview>(find.byType(ScheduleLayoutPreview))
          .settings
          .gridCellWidth,
      const ScheduleLayoutSettings().gridCellWidth,
    );
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

    await tester.drag(find.byType(ListView), const Offset(0, -250));
    await tester.pumpAndSettle();

    final resetWidth = find.byTooltip('重置网格宽度');
    expect(resetWidth, findsOneWidget);
    expect(find.byTooltip('重置网格高度'), findsNothing);

    await tester.tap(resetWidth);
    await tester.pumpAndSettle();

    expect(find.text('重置课表设置？'), findsNothing);
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
