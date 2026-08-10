import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/Mine/mine_menu_section.dart';
import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
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

  testWidgets('我的页面只保留一个统一设置入口', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MineMenuSection())),
    );

    expect(find.text('设置'), findsOneWidget);
    expect(find.text('主题设置'), findsNothing);
    expect(find.text('课程与体验'), findsNothing);
    expect(find.text('检查更新'), findsNothing);
    expect(find.text('清理缓存'), findsNothing);
    expect(find.text('关于我们'), findsNothing);
    expect(find.text('退出登录'), findsOneWidget);
  });

  testWidgets('设置中心仅展示五个分类入口', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AppSettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text('课表与课程'), findsOneWidget);
    expect(find.text('通知与提醒'), findsOneWidget);
    expect(find.text('外观与启动'), findsOneWidget);
    expect(find.text('存储与诊断'), findsOneWidget);
    expect(find.text('关于应用'), findsOneWidget);
    expect(find.text('显示周末'), findsNothing);
    expect(find.text('课前提醒'), findsNothing);
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

  testWidgets('已选择背景时显示透明度和模糊度设置', (tester) async {
    SharedPreferences.setMockInitialValues({
      'account': 'test-user',
      'schedule_background_image_path': 'test-background.jpg',
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
}
