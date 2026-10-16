import 'package:cqut_helper/pages/Settings/notification_settings_page.dart';
import 'package:cqut_helper/pages/Settings/settings_schedule_scope.dart';
import 'package:cqut_helper/utils/course_reminder_mode.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/widgets/app_select_field.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const channel = MethodChannel('cqut/course_reminders');

  void mockStatus({
    bool supported = true,
    required bool notificationGranted,
    bool exactAlarmGranted = true,
    bool dndGranted = true,
    bool Function(String kind)? onOpenSettings,
    Map<String, Object?> Function()? statusBuilder,
    VoidCallback? onStatus,
    VoidCallback? onRestore,
  }) {
    CourseReminderMode.debugIsAndroidOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getStatus') {
            onStatus?.call();
            return statusBuilder?.call() ??
                <String, Object?>{
                  'supported': supported,
                  'notificationGranted': notificationGranted,
                  'exactAlarmGranted': exactAlarmGranted,
                  'dndGranted': dndGranted,
                  'batteryOptimizationIgnored': false,
                  'autoModeActive': false,
                  'autoModeStatus': null,
                };
          }
          if (call.method == 'openSettings') {
            final kind = (call.arguments as Map)['kind'] as String;
            return onOpenSettings?.call(kind) ?? false;
          }
          if (call.method == 'cancelAndRestore') {
            onRestore?.call();
            return null;
          }
          return false;
        });
  }

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> chooseCourseMode(WidgetTester tester, String mode) async {
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<CourseAutoMode> &&
            widget.labelText == '上课勿扰与静音',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, mode));
    await tester.pumpAndSettle();
  }

  Future<void> pumpUntil(WidgetTester tester, bool Function() completed) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump();
      if (completed()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    await tester.pumpAndSettle();
  }

  bool courseModeEnabled(WidgetTester tester) =>
      tester
          .widget<AppSelectField<CourseAutoMode>>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AppSelectField<CourseAutoMode> &&
                  widget.labelText == '上课勿扰与静音',
            ),
          )
          .onChanged !=
      null;

  bool reminderChoiceEnabled(WidgetTester tester) =>
      tester
          .widget<AppSelectField<int>>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AppSelectField<int> && widget.labelText == '默认提前时间',
            ),
          )
          .onChanged !=
      null;

  tearDown(() {
    CourseReminderMode.debugIsAndroidOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('返回应用时刷新系统权限状态', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var notificationGranted = false;
    CourseReminderMode.debugIsAndroidOverride = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'getStatus');
          return <String, Object?>{
            'supported': true,
            'notificationGranted': notificationGranted,
            'exactAlarmGranted': true,
            'dndGranted': false,
            'batteryOptimizationIgnored': false,
            'autoModeActive': false,
            'autoModeStatus': 'off',
          };
        });

    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationSettingsPage(
          scope: SettingsScheduleScope(userId: '', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('通知权限'), findsOneWidget);
    expect(find.text('上课勿扰与静音'), findsNothing);
    final notificationTile = find.ancestor(
      of: find.text('通知权限'),
      matching: find.byType(ListTile),
    );
    expect(
      find.descendant(of: notificationTile, matching: find.text('未授权')),
      findsOneWidget,
    );

    notificationGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: notificationTile, matching: find.text('已授权')),
      findsOneWidget,
    );
  });

  testWidgets('首次授权状态读取失败后恢复时重建已开启的提醒', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
      'schedule_course_reminder_ids_v1': '[]',
    });
    CourseReminderMode.debugIsAndroidOverride = true;
    var statusRequests = 0;
    var restoreRequests = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getStatus') {
            statusRequests++;
            if (statusRequests == 1) {
              throw PlatformException(code: 'status_unavailable');
            }
            return <String, Object?>{
              'supported': true,
              'notificationGranted': true,
              'exactAlarmGranted': false,
              'dndGranted': false,
              'batteryOptimizationIgnored': false,
              'autoModeActive': false,
              'autoModeStatus': null,
            };
          }
          if (call.method == 'cancelAndRestore') {
            restoreRequests++;
            return null;
          }
          return false;
        });

    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationSettingsPage(
          scope: SettingsScheduleScope(userId: 'test-user', yearTerm: ''),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(statusRequests, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(statusRequests, 2);
    expect(prefs.getString('schedule_course_reminder_ids_v1'), isNull);
    expect(restoreRequests, 1);
    await pumpUntil(tester, () => courseModeEnabled(tester));
    expect(courseModeEnabled(tester), isTrue);
  });

  testWidgets('自定义提前时间校验失败保留设置，合法值可以保存', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
      'schedule_default_reminder_minutes': 15,
    });
    mockStatus(notificationGranted: true);
    await pumpPage(tester);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<int> && widget.labelText == '默认提前时间',
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).last, const Offset(0, -400));
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义…'));
    await tester.pumpAndSettle();
    final field = find.byType(TextFormField);
    final save = find.widgetWithText(FilledButton, '保存');
    final prefs = await SharedPreferences.getInstance();

    for (final invalid in ['0', '121', 'abc']) {
      await tester.enterText(field, invalid);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('请输入 1 到 120 之间的整数'), findsOneWidget);
      expect(prefs.getInt('schedule_default_reminder_minutes'), 15);
    }

    await tester.enterText(field, '37');
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(prefs.getInt('schedule_default_reminder_minutes'), 37);
    await pumpUntil(tester, () => reminderChoiceEnabled(tester));
    expect(reminderChoiceEnabled(tester), isTrue);
  });

  testWidgets('准时单独保存，不覆盖提前分钟数', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
      'schedule_default_reminder_minutes': 10,
    });
    mockStatus(notificationGranted: true);
    await pumpPage(tester);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<int> && widget.labelText == '默认提前时间',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('准时'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('schedule_default_reminder_at_start'), isTrue);
    expect(prefs.getInt('schedule_default_reminder_minutes'), 10);
    await pumpUntil(tester, () => reminderChoiceEnabled(tester));
    expect(reminderChoiceEnabled(tester), isTrue);
  });

  testWidgets('未开启课前提醒时隐藏自动模式', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mockStatus(notificationGranted: false);
    await pumpPage(tester);

    expect(find.text('上课勿扰与静音'), findsNothing);
  });

  testWidgets('设备不支持时禁用上课自动模式', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
    });
    mockStatus(supported: false, notificationGranted: true);
    await pumpPage(tester);

    expect(
      tester
          .widget<AppSelectField<CourseAutoMode>>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is AppSelectField<CourseAutoMode> &&
                  widget.labelText == '上课勿扰与静音',
            ),
          )
          .onChanged,
      isNull,
    );
  });
  testWidgets('取消勿扰授权不更改模式并解除控件禁用', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
    });
    var openSettingsCalls = 0;
    mockStatus(
      notificationGranted: true,
      dndGranted: false,
      onOpenSettings: (_) {
        openSettingsCalls++;
        return true;
      },
    );
    await pumpPage(tester);

    await chooseCourseMode(tester, '勿扰模式');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(openSettingsCalls, 0);
    expect(prefs.getString('schedule_course_auto_mode'), isNull);
    final field = tester.widget<AppSelectField<CourseAutoMode>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<CourseAutoMode> &&
            widget.labelText == '上课勿扰与静音',
      ),
    );
    expect(field.value, CourseAutoMode.off);
    expect(field.onChanged, isNotNull);
  });

  testWidgets('返回后勿扰授权成功才保存并解锁模式选择', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
    });
    var dndGranted = false;
    var openSettingsCalls = 0;
    var statusRequests = 0;
    var restoreRequests = 0;
    mockStatus(
      notificationGranted: true,
      statusBuilder: () => <String, Object?>{
        'supported': true,
        'notificationGranted': true,
        'exactAlarmGranted': true,
        'dndGranted': dndGranted,
        'batteryOptimizationIgnored': false,
        'autoModeActive': false,
        'autoModeStatus': null,
      },
      onStatus: () => statusRequests++,
      onRestore: () => restoreRequests++,
      onOpenSettings: (kind) {
        expect(kind, 'dnd');
        openSettingsCalls++;
        return true;
      },
    );
    await pumpPage(tester);
    final prefs = await SharedPreferences.getInstance();

    await chooseCourseMode(tester, '勿扰模式');
    await tester.tap(find.widgetWithText(FilledButton, '去设置'));
    await tester.pumpAndSettle();
    expect(prefs.getString('schedule_course_auto_mode'), isNull);

    dndGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => courseModeEnabled(tester));

    expect(openSettingsCalls, 1);
    expect(restoreRequests, 1);
    expect(statusRequests, 4);
    expect(prefs.getString('schedule_course_auto_mode'), 'dnd');
    final field = tester.widget<AppSelectField<CourseAutoMode>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<CourseAutoMode> &&
            widget.labelText == '上课勿扰与静音',
      ),
    );
    expect(field.value, CourseAutoMode.dnd);
    expect(field.onChanged, isNotNull);
  });

  testWidgets('精确闹钟权限缺失时引导授权并在返回后保存静音模式', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
    });
    var exactAlarmGranted = false;
    var openSettingsCalls = 0;
    var statusRequests = 0;
    var restoreRequests = 0;
    mockStatus(
      notificationGranted: true,
      statusBuilder: () => <String, Object?>{
        'supported': true,
        'notificationGranted': true,
        'exactAlarmGranted': exactAlarmGranted,
        'dndGranted': true,
        'batteryOptimizationIgnored': false,
        'autoModeActive': false,
        'autoModeStatus': null,
      },
      onStatus: () => statusRequests++,
      onRestore: () => restoreRequests++,
      onOpenSettings: (kind) {
        expect(kind, 'exactAlarm');
        openSettingsCalls++;
        return true;
      },
    );
    await pumpPage(tester);
    final prefs = await SharedPreferences.getInstance();

    await chooseCourseMode(tester, '静音');
    await tester.tap(find.widgetWithText(FilledButton, '去设置'));
    await tester.pumpAndSettle();
    expect(prefs.getString('schedule_course_auto_mode'), isNull);

    exactAlarmGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await pumpUntil(tester, () => courseModeEnabled(tester));

    expect(openSettingsCalls, 1);
    expect(restoreRequests, 1);
    expect(statusRequests, 4);
    expect(prefs.getString('schedule_course_auto_mode'), 'silent');
    final field = tester.widget<AppSelectField<CourseAutoMode>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<CourseAutoMode> &&
            widget.labelText == '上课勿扰与静音',
      ),
    );
    expect(field.value, CourseAutoMode.silent);
    expect(field.onChanged, isNotNull);
  });

  testWidgets('返回后勿扰权限仍未授权时保留原模式并允许重试', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
    });
    var openSettingsCalls = 0;
    mockStatus(
      notificationGranted: true,
      dndGranted: false,
      onOpenSettings: (_) {
        openSettingsCalls++;
        return true;
      },
    );
    await pumpPage(tester);
    final prefs = await SharedPreferences.getInstance();

    await chooseCourseMode(tester, '勿扰模式');
    await tester.tap(find.widgetWithText(FilledButton, '去设置'));
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(openSettingsCalls, 1);
    expect(prefs.getString('schedule_course_auto_mode'), isNull);
    final field = tester.widget<AppSelectField<CourseAutoMode>>(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppSelectField<CourseAutoMode> &&
            widget.labelText == '上课勿扰与静音',
      ),
    );
    expect(field.value, CourseAutoMode.off);
    expect(field.onChanged, isNotNull);
  });

  testWidgets('关闭上课勿扰与静音不要求系统授权', (tester) async {
    SharedPreferences.setMockInitialValues({
      'schedule_course_reminders_enabled': true,
    });
    var openSettingsCalls = 0;
    mockStatus(
      notificationGranted: false,
      exactAlarmGranted: false,
      dndGranted: false,
      onOpenSettings: (_) {
        openSettingsCalls++;
        return true;
      },
    );
    await pumpPage(tester);

    await chooseCourseMode(tester, '关闭');

    final prefs = await SharedPreferences.getInstance();
    expect(openSettingsCalls, 0);
    expect(prefs.getString('schedule_course_auto_mode'), 'off');
  });
}
