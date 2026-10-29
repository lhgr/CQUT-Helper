import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker_health.dart';
import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/course_preference_model.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/pages/Login/ForgetPassword.dart';
import 'package:cqut_helper/pages/Guide/usage_guide_page.dart';
import 'package:cqut_helper/pages/Announcement/Announcement.dart';
import 'package:cqut_helper/pages/ClassSchedule/ClassSchedule.dart';
import 'package:cqut_helper/pages/ClassSchedule/custom_course_editor_page.dart';
import 'package:cqut_helper/pages/ClassSchedule/course_preference_editor.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/course_detail_dialog.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/hidden_courses_sheet.dart';
import 'package:cqut_helper/pages/Mine/Mine.dart';
import 'package:cqut_helper/pages/Mine/ClearCache.dart';
import 'package:cqut_helper/pages/Mine/mine_theme_settings_sheet.dart';
import 'package:cqut_helper/pages/Main/Main.dart';
import 'package:cqut_helper/pages/MessageCenter/message_center_page.dart';
import 'package:cqut_helper/pages/Settings/about_settings_page.dart';
import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
import 'package:cqut_helper/pages/Settings/appearance_startup_settings_page.dart';
import 'package:cqut_helper/pages/Settings/backup_restore_page.dart';
import 'package:cqut_helper/pages/Settings/notification_settings_page.dart';
import 'package:cqut_helper/pages/Settings/schedule_background_crop_page.dart';
import 'package:cqut_helper/pages/Settings/schedule_courses_settings_page.dart';
import 'package:cqut_helper/pages/Settings/schedule_layout_preview.dart';
import 'package:cqut_helper/pages/Settings/settings_schedule_scope.dart';
import 'package:cqut_helper/pages/Settings/sync_diagnostics_page.dart';
import 'package:cqut_helper/pages/Settings/sync_diagnostics_service.dart';
import 'package:cqut_helper/pages/TodaySchedule/TodaySchedule.dart';
import 'package:cqut_helper/theme/app_theme.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';

const _capture = bool.fromEnvironment('CAPTURE_EXPRESSIVE');
const _captureKey = ValueKey('expressive-capture');
const _user = 'visual-test';
const _term = '2026-2027-1';
String? _fontFamily;
late Map<String, Object?> _scheduleRow;
bool _scheduleAvailable = true;
late WorkmanagerPlatform _originalWorkmanager;

class _VisualSyncDiagnosticsService extends SyncDiagnosticsService {
  @override
  Future<SyncDiagnosticsSnapshot> load() async {
    final now = DateTime.now();
    return SyncDiagnosticsSnapshot(
      account: '2026001001',
      hasCredential: true,
      remindersEnabled: true,
      enhancementEnabled: true,
      cachedWeeks: 2,
      refresh: ScheduleRefreshSnapshot(
        lastSuccessfulRefreshAt: now.subtract(const Duration(minutes: 5)),
        widgetState: ScheduleWidgetRefreshState.idle,
        failure: null,
      ),
      reminders: CourseReminderStatus(
        enabled: true,
        ready: true,
        reason: '提醒已安排',
        scheduledCount: 4,
        cachedWeekCount: 2,
        expectedWeekCount: 2,
        nextReminderAt: now.add(const Duration(hours: 1)),
        updatedAt: now,
      ),
      notifications: true,
      exactAlarm: true,
      background: ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.healthy,
        title: '后台运行正常',
        detail: '后台检查按计划运行',
        lastRunAt: now.subtract(const Duration(minutes: 10)),
        lastSuccessAt: now.subtract(const Duration(minutes: 10)),
      ),
      batteryIgnored: true,
      backgroundRestricted: false,
    );
  }

  @override
  void logFailure(String operation, Object error, StackTrace stack) {}
}
DatabaseFactory? _originalDatabaseFactory;

class _VisualWorkmanager extends WorkmanagerPlatform {
  @override
  Future<void> registerOneOffTask(
    String uniqueName,
    String taskName, {
    Map<String, dynamic>? inputData,
    Duration? initialDelay,
    Constraints? constraints,
    ExistingWorkPolicy? existingWorkPolicy,
    BackoffPolicy? backoffPolicy,
    Duration? backoffPolicyDelay,
    String? tag,
    OutOfQuotaPolicy? outOfQuotaPolicy,
    ForegroundServiceConfig? foregroundServiceConfig,
    bool expedited = false,
  }) async {}

  @override
  Future<void> cancelByUniqueName(String uniqueName) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    _originalWorkmanager = WorkmanagerPlatform.instance;
    _originalDatabaseFactory = databaseFactoryOrNull;
    databaseFactoryOrNull = databaseFactorySqflitePlugin;
    WorkmanagerPlatform.instance = _VisualWorkmanager();
    // Use the installed CJK font when producing review images on Windows.
    // Regular test runs retain Flutter's deterministic test font.
    final font = File(r'C:\Windows\Fonts\msyh.ttc');
    if (_capture && font.existsSync()) {
      final fontBytes = ByteData.sublistView(await font.readAsBytes());
      for (final family in ['ExpressiveReview', 'Roboto', 'Ahem']) {
        await (FontLoader(family)..addFont(Future.value(fontBytes))).load();
      }
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      _fontFamily = 'ExpressiveReview';
    }
  });

  tearDownAll(() {
    WorkmanagerPlatform.instance = _originalWorkmanager;
    databaseFactoryOrNull = _originalDatabaseFactory;
  });

  setUp(() {
    _scheduleAvailable = true;
    final now = DateTime.now();
    String clock(int minute) =>
        '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
    final nowMinute = now.hour * 60 + now.minute;
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final schedule = ScheduleData(
      yearTerm: _term,
      nowMonth: '${now.month}',
      yearTermList: const [_term],
      weekNum: '7',
      weekList: List.generate(20, (index) => '${index + 1}'),
      weekDayList: List.generate(7, (index) {
        final date = monday.add(Duration(days: index));
        return WeekDayItem(
          weekDay: '${index + 1}',
          weekDate:
              '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
          today: index + 1 == now.weekday,
        );
      }),
      eventList: [
        EventItem(
          eventName: '数字图像处理',
          weekList: const ['7'],
          weekDay: '${now.weekday}',
          sessionList: ['1', '2'],
          sessionStart: '1',
          sessionLast: '2',
          address: '花溪校区 · 第三教学楼 302',
          memberName: '张老师',
        ),
        EventItem(
          eventName: '操作系统',
          weekList: const ['7'],
          weekDay: '${now.weekday}',
          sessionList: ['5', '6'],
          sessionStart: '5',
          // sessionLast is the number of consecutive sessions, not the ending
          // session index. The course therefore spans sessions 5 and 6.
          sessionLast: '2',
          address: '花溪校区 · 实验楼 201',
          memberName: '李老师',
        ),
      ],
    );
    final raw = jsonEncode(schedule.toJson());
    _scheduleRow = {
      'user_id': _user,
      'year_term': _term,
      'week_num': '7',
      'raw_json': raw,
      'checksum': ScheduleCacheDatabase.checksumFor(raw),
      'fetched_at': now.millisecondsSinceEpoch,
      'last_verified_at': now.millisecondsSinceEpoch,
      'data_version': ScheduleCacheDatabase.dataVersion,
    };
    final calendar = AcademicCalendarSnapshot(
      schemaVersion: 1,
      yearTerm: _term,
      revision: 'visual-test',
      generatedAt: now,
      complete: true,
      days: const [],
    );
    SharedPreferences.setMockInitialValues({
      'account': _user,
      'schedule_last_week_$_user': '7',
      'schedule_last_term_$_user': _term,
      'schedule_time_info_enabled': false,
      'schedule_show_weekend': true,
      'schedule_polling_guide_shown_$_user': true,
      'announcement_cache_ts_v1': now.millisecondsSinceEpoch,
      'announcement_cache_items_v1': jsonEncode([
        {
          'id': 'visual-announcement',
          'title': '秋季学期课表使用说明',
          'contentMarkdown': '## 课表与课程\n请及时同步本学期课程，查看课程时间与地点。',
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        },
      ]),
      'schedule_message_history_v1_$_user': jsonEncode([
        {
          'id': 'visual-change',
          'userId': _user,
          'yearTerm': _term,
          'createdAt': now.toIso8601String(),
          'read': false,
          'changes': [
            {
              'weekNum': '7',
              'lines': ['数字图像处理：上课地点调整为第三教学楼 302'],
            },
          ],
        },
      ]),
      'schedule_time_info_cache_v1': jsonEncode({
        'campusName': '花溪校区',
        'updatedAt': now.millisecondsSinceEpoch,
        'items': [
          for (var session = 1; session <= 6; session++)
            CampusTimeInfo(
              campusName: '花溪校区',
              sessionNum: session,
              startTime: clock((nowMinute - 20).clamp(0, 1438)),
              endTime: clock((nowMinute + 100).clamp(1, 1439)),
            ).toJson(),
        ],
      }),
      'schedule_default_home_tab': 2,
      'daily_quote_cache_ts_v1': now.millisecondsSinceEpoch,
      'daily_quote_config_v1': jsonEncode({
        'enabled': true,
        'revision': 1,
        'rotationMode': 'daily',
        'items': [
          {
            'id': 'visual-first',
            'text': '把平凡的每一天，过成自己的好时光。',
            'source': '校园一言',
            'priority': 100,
          },
          {'id': 'visual-second', 'text': '慢慢来，每一步都有意义。'},
        ],
      }),
      'academic_calendar_snapshot_v1_$_term': calendar.encode(),
      'academic_calendar_checked_at_v1_$_term': now.millisecondsSinceEpoch,
      'user_info_$_user': jsonEncode({
        'username': '2026001001',
        'userRealName': '陈同学',
        'userCustomSetting': {'campusName': '花溪校区'},
      }),
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    PackageInfo.setMockInitialValues(
      appName: 'CQUT Helper',
      packageName: 'com.example.cqut_helper',
      version: '1.2.1',
      buildNumber: '2015',
      buildSignature: '',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'be.tramckrijte.workmanager/foreground_channel_work_manager',
      ),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async => null,
    );
    // Feed the real cache reader deterministic rows through its platform boundary.
    // Every screenshot still renders the production page and its normal widgets.
    messenger.setMockMethodCallHandler(
      const MethodChannel('com.tekartik.sqflite'),
      (call) async {
        final args = call.arguments as Map?;
        switch (call.method) {
          case 'getDatabasesPath':
            return Directory.systemTemp.path;
          case 'openDatabase':
            return {
              'id': (args?['path'] as String? ?? '').contains('customizations')
                  ? 2
                  : 1,
            };
          case 'query':
            final sql = args?['sql'] as String? ?? '';
            if (sql.contains('COUNT(')) {
              return [
                {'count': 1},
              ];
            }
            if (sql.contains(' AS bytes')) {
              return [
                {'bytes': 512},
              ];
            }
            if (sql.contains('user_version')) {
              return [
                {'user_version': 2},
              ];
            }
            if (sql.contains('cache_meta')) {
              return [
                {'value': '1'},
              ];
            }
            if (sql.contains('schedule_weeks')) {
              if (!_scheduleAvailable) return <Map<String, Object?>>[];
              final arguments = args?['arguments'] as List? ?? const [];
              if (sql.contains('week_num = ?') &&
                  arguments.length >= 3 &&
                  arguments[2] != _scheduleRow['week_num']) {
                return <Map<String, Object?>>[];
              }
              return [_scheduleRow];
            }
            return <Map<String, Object?>>[];
          case 'execute':
            if ((args?['sql'] as String? ?? '').startsWith('BEGIN')) {
              return {'transactionId': 1};
            }
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in [
      'plugins.it_nomads.com/flutter_secure_storage',
      'com.tekartik.sqflite',
      'be.tramckrijte.workmanager/foreground_channel_work_manager',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('onboarding visual covers new user pages and cached schedule', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_is_new_user', true);
    final onboarding = OnboardingManager.instance;
    await onboarding.initialize();
    await prefs.setString('schedule_message_history_v1_$_user', '[]');

    for (final scenario in [
      ('light-390', Brightness.light, 390.0, 1.0),
      ('dark-390', Brightness.dark, 390.0, 1.0),
      ('light-320-large', Brightness.light, 320.0, 2.0),
      ('dark-320-large', Brightness.dark, 320.0, 2.0),
    ]) {
      final (label, brightness, width, scale) = scenario;

      await _pumpPage(tester, const LoginPage(), width, brightness, scale);
      expect(find.text('登录后自动同步课表，已同步的课程可离线查看。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'onboarding-login-$label');
      if (scale >= 2) {
        final loginButton = find.widgetWithText(FilledButton, '登录');
        await tester.ensureVisible(loginButton);
        expect(loginButton.hitTestable(), findsOneWidget);
      }
      await tester.pumpWidget(const SizedBox.shrink());

      final background = label == 'dark-390'
          ? ScheduleLayoutSettings(
              backgroundImagePath:
                  '${Directory.current.path}/lib/assets/Icon.png',
            )
          : null;

      await _pumpPage(
        tester,
        const ClassscheduleView(),
        width,
        brightness,
        scale,
        scheduleBackground: background,
      );
      expect(find.textContaining('数字图像处理', findRichText: true), findsWidgets);
      expect(onboarding.scheduleReady, isTrue);
      expect(find.textContaining('点顶部周次'), findsOneWidget);
      await _revealCachedCourse(tester);
      if (label == 'light-390') {
        // The visual fixture has a valid local cache and no saved credential,
        // so a manual refresh takes the real local failure path without a
        // network request. The cached schedule and hint should remain usable.
        await tester.tap(find.widgetWithIcon(IconButton, Icons.refresh));
        await tester.pumpAndSettle();
        expect(onboarding.showScheduleHint, isTrue);
        expect(find.textContaining('点顶部周次'), findsOneWidget);
        expect(find.textContaining('数字图像处理', findRichText: true), findsWidgets);
      }
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'onboarding-schedule-cache-$label');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));

      await _pumpPage(tester, const MineView(), width, brightness, scale);
      expect(find.text('按需设置'), findsOneWidget);
      expect(find.text('课前提醒'), findsOneWidget);
      expect(find.text('桌面小组件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'onboarding-mine-$label');
      await tester.pumpWidget(const SizedBox.shrink());

      await _pumpPage(tester, const UsageGuidePage(), width, brightness, scale);
      expect(find.text('课表缓存后可离线查看。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'onboarding-guide-$label');
      await tester.pumpWidget(const SizedBox.shrink());
    }

    await onboarding.dismissScheduleHint();
    await onboarding.dismissOptionalFeatures();
  });

  testWidgets('today represents next course and finished day', (tester) async {
    final now = DateTime.now();
    final minute = now.hour * 60 + now.minute;
    // Relative times exercise production countdown selection without changing
    // the page clock or adding a test-only production constructor.
    if (minute < 1420) {
      await _setTodayTimes(start: minute + 10, end: minute + 30);
      await _pumpPage(
        tester,
        const TodayScheduleView(),
        390,
        Brightness.light,
        1,
      );
      expect(find.text('下一节课'), findsOneWidget);
      expect(find.textContaining('10分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'today-next-light-390');
      await tester.pumpWidget(const SizedBox.shrink());
    }
    if (minute > 30) {
      await _setTodayTimes(start: minute - 30, end: minute - 10);
      await _pumpPage(
        tester,
        const TodayScheduleView(),
        390,
        Brightness.dark,
        1,
      );
      expect(find.text('今日课程已结束'), findsOneWidget);
      expect(find.text('数字图像处理'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'today-finished-dark-390');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final state in [
    'no-courses',
    'holiday',
    'outside-week',
    'missing-source',
    'mapped',
  ]) {
    testWidgets('today $state preserves calendar meaning', (tester) async {
      final now = DateTime.now();
      final data = _fixtureSchedule();
      if (state == 'no-courses') data.eventList = [];
      if (state == 'outside-week') {
        for (var index = 0; index < data.weekDayList!.length; index++) {
          final date = now.add(Duration(days: 14 + index));
          data.weekDayList![index].weekDate =
              '${date.year}-${date.month}-${date.day}';
        }
      }
      if (state == 'holiday' ||
          state == 'missing-source' ||
          state == 'mapped') {
        final source = state == 'mapped'
            ? now.add(Duration(days: now.weekday == 7 ? -1 : 1))
            : now.add(const Duration(days: 28));
        if (state == 'mapped') {
          data.eventList = [
            data.eventList!.first..weekDay = '${source.weekday}',
          ];
        }
        await _setCalendar([
          AcademicCalendarDay(
            date: now,
            kind: state == 'holiday'
                ? AcademicCalendarDayKind.holiday
                : AcademicCalendarDayKind.teachingDay,
            label: state == 'holiday' ? '校历假日' : '调休安排',
            scheduleDate: state == 'holiday' ? null : source,
          ),
        ]);
      }
      _replaceFixtureSchedule(data);
      await _pumpPage(
        tester,
        const TodayScheduleView(),
        390,
        Brightness.light,
        1,
      );
      switch (state) {
        case 'no-courses':
          expect(find.text('今天没课'), findsOneWidget);
        case 'holiday':
          expect(find.text('今日放假'), findsOneWidget);
          expect(find.textContaining('校历假日'), findsOneWidget);
          expect(find.text('数字图像处理'), findsNothing);
        case 'outside-week':
          expect(find.text('当前不在教学周'), findsOneWidget);
        case 'missing-source':
          expect(find.text('调休课表尚未加载'), findsOneWidget);
          expect(find.text('数字图像处理'), findsNothing);
        case 'mapped':
          expect(find.text('数字图像处理'), findsWidgets);
          expect(find.textContaining('调休：原'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'today-$state-light-390');
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('today missing credentials offers retry and login', (
    tester,
  ) async {
    _scheduleAvailable = false;
    await _pumpPage(
      tester,
      const TodayScheduleView(),
      320,
      Brightness.light,
      1.6,
    );
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('重新登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _capturePage(tester, 'today-error-light-320-large');
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('重新登录'), findsOneWidget);
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginPage), findsOneWidget);
    expect(
      tester.widget<LoginPage>(find.byType(LoginPage)).reauthenticate,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final scenario in [
    ('light-390', Brightness.light, 390.0, 1.0),
    ('dark-390', Brightness.dark, 390.0, 1.0),
    ('light-320-large', Brightness.light, 320.0, 1.6),
    ('dark-320-large', Brightness.dark, 320.0, 1.6),
  ]) {
    final (label, brightness, width, scale) = scenario;

    testWidgets('login $label keeps inputs and password toggle usable', (
      tester,
    ) async {
      await _pumpPage(tester, const LoginPage(), width, brightness, scale);
      await tester.enterText(find.byType(TextFormField).first, '2026001001');
      await tester.enterText(
        find.byType(TextFormField).last,
        'example-password',
      );
      await tester.ensureVisible(find.byTooltip('显示密码'));
      await tester.tap(find.byTooltip('显示密码'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField).last).obscureText,
        isFalse,
      );
      expect(find.text('2026001001'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'login-$label');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'mine $label opens settings and preserves the profile on return',
      (tester) async {
        await _pumpPage(tester, const MineView(), width, brightness, scale);
        expect(find.text('陈同学'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturePage(tester, 'mine-$label');
        await tester.ensureVisible(find.text('设置'));
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.byType(AppSettingsPage), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturePage(tester, 'settings-$label');
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();
        expect(find.text('陈同学'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('today $label renders cached courses without overflow', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const TodayScheduleView(),
        width,
        brightness,
        scale,
      );
      expect(
        find.text('数字图像处理'),
        findsWidgets,
        reason: tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data)
            .join(' | '),
      );
      expect(find.textContaining('1小时40分钟'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'today-$label');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('today long content $label opens details and refreshes cache', (
      tester,
    ) async {
      const name = '数字图像处理与计算机视觉综合实践课程设计';
      const location = '花溪校区第三教学楼与工程训练中心联合实验室 A 区 302';
      const note = '请携带笔记本电脑，提前阅读实验指导书，准备本周课程汇报材料。';
      final data = _fixtureSchedule();
      data.eventList!.first
        ..eventName = name
        ..address = location
        ..note = note;
      data.eventList!.last
        ..memberName = null
        ..address = null
        ..note = null;
      _replaceFixtureSchedule(data);
      await _pumpPage(
        tester,
        const TodayScheduleView(),
        width,
        brightness,
        scale,
      );
      expect(find.text(name), findsWidgets);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'today-long-$label');

      // Open the real course row rather than testing the dialog in isolation.
      final course = find.text(name).last;
      await tester.ensureVisible(course);
      await tester.tap(course);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining(location), findsWidgets);
      expect(find.textContaining(note), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      final quote = find.text('换一句');
      await tester.ensureVisible(quote);
      await tester.pumpAndSettle();
      expect(find.text('地点：null'), findsNothing);
      expect(find.text('教师：null'), findsNothing);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'today-long-list-end-$label');
      await tester.tap(quote);
      await tester.pumpAndSettle();
      expect(find.text('慢慢来，每一步都有意义。'), findsOneWidget);
      expect(find.text('把平凡的每一天，过成自己的好时光。'), findsNothing);

      await tester.drag(find.byType(ListView).first, const Offset(0, 2400));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(find.text(name), findsWidgets);
      expect(find.text('请重新登录后刷新，正在显示已保存课表。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('schedule $label loads the real page and opens both pickers', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const ClassscheduleView(),
        width,
        brightness,
        scale,
      );
      expect(find.textContaining('数字图像处理', findRichText: true), findsWidgets);
      expect(find.byType(ScheduleLayoutPreview), findsNothing);
      await _revealCachedCourse(tester);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'schedule-$label');
      await tester.tap(find.byTooltip('第7周'));
      await tester.pumpAndSettle();
      expect(find.text('选择周次'), findsOneWidget);
      await _capturePage(tester, 'week-picker-$label');
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('20'), findsWidgets);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('$_term学期'));
      await tester.pumpAndSettle();
      expect(find.text('选择学期'), findsOneWidget);
      expect(find.textContaining(_term), findsWidgets);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'term-picker-$label');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    });

    const scope = SettingsScheduleScope(userId: _user, yearTerm: _term);
    for (final page in <(String, Widget, String)>[
      (
        'settings-courses',
        const ScheduleCoursesSettingsPage(scope: scope),
        '显示周末',
      ),
      (
        'settings-notifications',
        const NotificationSettingsPage(scope: scope),
        '课前提醒',
      ),
      ('settings-appearance', const AppearanceStartupSettingsPage(), '主题模式'),
      (
        'settings-diagnostics',
        SyncDiagnosticsPage(service: _VisualSyncDiagnosticsService()),
        '同步与修复',
      ),
      ('settings-backup', const BackupRestorePage(), '导出备份文件'),
      ('settings-storage', const ClearCachePage(), '课表缓存'),
      ('settings-about', const AboutSettingsPage(), '版本 1.2.1'),
    ]) {
      testWidgets('${page.$1} $label loads content and scrolls to the end', (
        tester,
      ) async {
        await _pumpPage(tester, page.$2, width, brightness, scale);
        expect(find.text(page.$3), findsWidgets);
        if (page.$1 == 'settings-diagnostics') {
          expect(find.text('提醒就绪状态'), findsOneWidget);
          expect(find.text('调课通知增强'), findsOneWidget);
        }
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(tester.takeException(), isNull, reason: page.$1);
        await _capturePage(tester, '${page.$1}-$label');
        await tester.drag(find.byType(ListView).first, const Offset(0, -2400));
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '${page.$1} after scroll',
        );
        await _capturePage(tester, '${page.$1}-end-$label');
        if (page.$1 == 'settings-diagnostics') {
          await tester.tap(find.text('查看详情'));
          await tester.pumpAndSettle();
          final backgroundSuccess = find.textContaining('后台最近成功：');
          await tester.ensureVisible(backgroundSuccess);
          await tester.pumpAndSettle();
          expect(backgroundSuccess.hitTestable(), findsOneWidget);
          expect(
            tester.takeException(),
            isNull,
            reason: '${page.$1} details expanded',
          );
          await _capturePage(tester, '${page.$1}-details-$label');
        }
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }

    testWidgets('layout $label keeps preview and save actions available', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const ScheduleCoursesSettingsPage(
          scope: SettingsScheduleScope(userId: _user, yearTerm: _term),
        ),
        width,
        brightness,
        scale,
      );
      final entry = find.byKey(
        const ValueKey('schedule-layout-settings-entry'),
      );
      await tester.ensureVisible(entry);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleLayoutPreview), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'settings-layout-$label');
      await tester.ensureVisible(find.text('显示网格线'));
      await tester.pumpAndSettle();
      expect(find.text('显示网格线').hitTestable(), findsOneWidget);
      await tester.tap(find.text('显示网格线'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '重置'));
      await tester.pumpAndSettle();
      expect(find.text('确认重置'), findsOneWidget);
      expect(find.text('取消').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'layout-reset-$label');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '保存'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(find.text('布局与外观已保存'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('messages and announcements $label show fixture content', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        const MessageCenterPage(),
        width,
        brightness,
        scale,
      );
      expect(find.text('暂无课表变更记录'), findsNothing);
      expect(find.text('课表变更记录'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'messages-$label');
      await tester.ensureVisible(find.byType(ExpansionTile));
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();
      final change = find.textContaining('数字图像处理：上课地点调整为第三教学楼 302');
      await tester.ensureVisible(change);
      expect(change.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'messages-expanded-$label');
      await _pumpPage(
        tester,
        const AnnouncementListPage(),
        width,
        brightness,
        scale,
      );
      expect(find.text('秋季学期课表使用说明'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'announcements-$label');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'password recovery and course editor $label expose primary actions',
      (tester) async {
        await _pumpPage(
          tester,
          const ForgetPasswordPage(),
          width,
          brightness,
          scale,
        );
        await tester.enterText(find.byType(TextFormField), '13800138000');
        await tester.ensureVisible(find.text('发送验证码'));
        expect(find.text('发送验证码').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturePage(tester, 'password-recovery-$label');
        await _pumpPage(
          tester,
          CustomCourseEditorPage(
            userId: _user,
            encryptedPassword: 'fixture',
            yearTerm: _term,
            availableWeeks: List.generate(20, (index) => index + 1),
            initial: EventItem(
              eventName: '数字图像处理实验',
              memberName: '张老师',
              address: '第三教学楼 302',
              weekList: const ['7'],
              weekDay: '3',
              sessionStart: '5',
              sessionLast: '2',
              eventID: 'fixture',
            ),
          ),
          width,
          brightness,
          scale,
        );
        expect(find.text('数字图像处理实验'), findsOneWidget);
        expect(find.text('保存').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturePage(tester, 'custom-course-$label');
        await tester.drag(find.byType(ListView), const Offset(0, -2400));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await _capturePage(tester, 'custom-course-end-$label');
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('course detail $label scrolls content and exposes actions', (
      tester,
    ) async {
      var edited = false;
      await _pumpPage(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCourseDetailDialog(
                context,
                courseName: '数字图像处理与计算机视觉实验',
                events: [
                  EventItem(
                    eventName: '数字图像处理与计算机视觉实验',
                    memberName: '张老师',
                    address: '花溪校区 · 第三教学楼 302',
                    weekCover: '第1–20周',
                    note: List.filled(6, '请携带笔记本电脑，提前阅读实验指导书。').join('\n'),
                    weekDay: '3',
                    sessionStart: '5',
                    sessionLast: '2',
                  ),
                ],
                onEdit: (_) async => edited = true,
              ),
              child: const Text('打开详情'),
            ),
          ),
        ),
        width,
        brightness,
        scale,
      );
      await tester.tap(find.text('打开详情'));
      await tester.pumpAndSettle();
      expect(find.text('数字图像处理与计算机视觉实验'), findsOneWidget);
      await tester.ensureVisible(find.text('编辑'));
      expect(find.text('编辑').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'course-detail-$label');
      await tester.tap(find.text('编辑'));
      await tester.pumpAndSettle();
      expect(edited, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('theme sheet $label scrolls to its color controls', (
      tester,
    ) async {
      await ThemeManager().setSystemColor(true);
      await _pumpPage(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showThemeSettingsSheet(context),
              child: const Text('打开主题'),
            ),
          ),
        ),
        width,
        brightness,
        scale,
      );
      await tester.tap(find.text('打开主题'));
      await tester.pumpAndSettle();
      expect(find.text('主题设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'theme-sheet-$label');
      await tester.ensureVisible(find.text('跟随系统主题色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('跟随系统主题色'));
      await tester.pumpAndSettle();
      expect(find.text('主题颜色'), findsOneWidget);
      await tester.drag(
        find.byType(SingleChildScrollView).last,
        const Offset(0, -900),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final swatches = find.byWidgetPredicate((widget) {
        if (widget is! GestureDetector || widget.child is! SizedBox) {
          return false;
        }
        final target = widget.child! as SizedBox;
        return target.width == 48 && target.height == 48;
      });
      expect(swatches, findsNWidgets(12));
      expect(tester.getSize(swatches.last), const Size(48, 48));
      expect(swatches.last.hitTestable(), findsOneWidget);
      await _capturePage(tester, 'theme-sheet-colors-$label');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('course preferences $label expose editable content and save', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showCoursePreferenceEditor(
                context,
                userId: _user,
                yearTerm: _term,
                courseKey: 'visual-course',
                currentName: '数字图像处理',
                currentTeacher: '张老师',
                currentLocation: '第三教学楼 302',
                initial: null,
              ),
              child: const Text('打开课程偏好'),
            ),
          ),
        ),
        width,
        brightness,
        scale,
      );
      await tester.tap(find.text('打开课程偏好'));
      await tester.pumpAndSettle();
      expect(find.text('数字图像处理'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'course-preferences-$label');
      final save = find.byType(FilledButton);
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'course-preferences-end-$label');
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.text('打开课程偏好'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets(
      'hidden courses $label load real sheet rows and restore a course',
      (tester) async {
        var restored = false;
        final preference = CoursePreference(
          userId: _user,
          yearTerm: _term,
          courseKey: 'visual-hidden',
          displayName: null,
          teacher: null,
          location: null,
          note: '',
          hidden: true,
          reminderMinutes: null,
          colorIndex: null,
          updatedAt: DateTime(2026),
        );
        await _pumpPage(
          tester,
          Scaffold(
            body: HiddenCoursesSheet(
              userId: _user,
              yearTerm: _term,
              loadCourses: () async => restored
                  ? []
                  : [
                      HiddenCourseInfo(
                        preference: preference,
                        cachedEvent: EventItem(
                          eventName: '数字图像处理',
                          memberName: '张老师',
                          address: '第三教学楼 302',
                        ),
                      ),
                    ],
              onRestore: (_) async => restored = true,
            ),
          ),
          width,
          brightness,
          scale,
        );
        expect(find.text('数字图像处理'), findsOneWidget);
        await tester.ensureVisible(find.text('取消隐藏'));
        await tester.pumpAndSettle();
        expect(find.text('取消隐藏').hitTestable(), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _capturePage(tester, 'hidden-courses-$label');
        await tester.tap(find.text('取消隐藏'));
        await tester.pumpAndSettle();
        expect(restored, isTrue);
        expect(find.text('暂无隐藏课程'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );

    testWidgets('background crop $label decodes an image fixture', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        ScheduleBackgroundCropPage(
          imagePath: '${Directory.current.path}/lib/assets/Icon.png',
          targetAspectRatio: width / 844,
        ),
        width,
        brightness,
        scale,
      );
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('无法读取图片，请重新选择背景图片'), findsNothing);
      expect(find.byType(RawImage), findsOneWidget);
      expect(find.text('确定裁切').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'background-crop-$label');
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('main $label keeps navigation visible and tabs alive', (
      tester,
    ) async {
      await _pumpPage(tester, const MainPage(), width, brightness, scale);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.text('陈同学'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'main-mine-$label');
      await tester.tap(find.text('课表').last);
      await tester.pumpAndSettle();
      expect(find.byType(ClassscheduleView), findsOneWidget);
      expect(find.textContaining('数字图像处理', findRichText: true), findsWidgets);
      await _revealCachedCourse(tester);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'main-schedule-$label');
      await tester.tap(find.text('今日'));
      await tester.pumpAndSettle();
      expect(find.byType(TodayScheduleView), findsOneWidget);
      expect(find.text('数字图像处理'), findsWidgets);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'main-today-$label');
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(find.text('陈同学'), findsOneWidget);
      await tester.tap(find.text('今日').last);
      await tester.pumpAndSettle();
      expect(find.byType(TodayScheduleView), findsOneWidget);
      expect(find.text('数字图像处理'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 200));
    });
  }
}

ScheduleData _fixtureSchedule() => ScheduleData.fromJson(
  (jsonDecode(_scheduleRow['raw_json'] as String) as Map)
      .cast<String, dynamic>(),
);

void _replaceFixtureSchedule(ScheduleData data) {
  final raw = jsonEncode(data.toJson());
  _scheduleRow = {
    ..._scheduleRow,
    'raw_json': raw,
    'checksum': ScheduleCacheDatabase.checksumFor(raw),
  };
}

Future<void> _setTodayTimes({required int start, required int end}) async {
  String clock(int minute) =>
      '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'schedule_time_info_cache_v1',
    jsonEncode({
      'campusName': '花溪校区',
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'items': [
        for (var session = 1; session <= 6; session++)
          CampusTimeInfo(
            campusName: '花溪校区',
            sessionNum: session,
            startTime: clock(start),
            endTime: clock(end),
          ).toJson(),
      ],
    }),
  );
}

Future<void> _setCalendar(List<AcademicCalendarDay> days) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(
    'academic_calendar_snapshot_v1_$_term',
    AcademicCalendarSnapshot(
      schemaVersion: 1,
      yearTerm: _term,
      revision: 'visual-state',
      generatedAt: DateTime.now(),
      complete: true,
      days: days,
    ).encode(),
  );
}

Future<void> _revealCachedCourse(WidgetTester tester) async {
  final course = find.textContaining('数字图像处理', findRichText: true).first;
  await Scrollable.ensureVisible(tester.element(course), alignment: 0.5);
  await tester.pumpAndSettle();
  expect(course.hitTestable(), findsOneWidget);
  expect(find.byType(CircularProgressIndicator), findsNothing);
  expect(find.text('重试'), findsNothing);
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page,
  double width,
  Brightness brightness,
  double scale, {
  bool settle = true,
  ScheduleLayoutSettings? scheduleBackground,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    // Let any already-running prefetch interval observe controller disposal.
    await tester.pump(const Duration(milliseconds: 200));
  });
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff467B6F),
    brightness: brightness,
  );
  var theme = brightness == Brightness.dark
      ? AppTheme.dark(scheme)
      : AppTheme.light(scheme);
  if (_fontFamily != null) {
    theme = theme.copyWith(
      textTheme: theme.textTheme.apply(fontFamily: _fontFamily),
    );
  }
  final app = RepaintBoundary(
    key: _captureKey,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: page is ClassscheduleView && scheduleBackground != null
          ? Stack(
              fit: StackFit.expand,
              children: [
                ScheduleBackground(settings: scheduleBackground),
                page,
              ],
            )
          : page is ClassscheduleView
          ? ColoredBox(color: theme.scaffoldBackgroundColor, child: page)
          : page,
    ),
  );
  if (page is ScheduleBackgroundCropPage) {
    await tester.runAsync(() async {
      await tester.pumpWidget(app);
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  } else {
    final backgroundPath = scheduleBackground?.backgroundImagePath;
    if (backgroundPath != null && backgroundPath.trim().isNotEmpty) {
      await tester.runAsync(
        () => ScheduleBackground.preloadFile(backgroundPath),
      );
    }
    await tester.pumpWidget(app);
  }
  if (_capture) {
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('lib/assets/Icon.png'),
        tester.element(find.byKey(_captureKey)),
      );
    });
  }
  // File/image decoding and filesystem-backed cache size reads need actual
  // asynchronous work; fake widget time alone cannot complete these futures.
  for (var attempt = 0; attempt < 4; attempt++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 40));
    });
    await tester.pump();
  }
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _capturePage(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_captureKey),
  );
  await tester.runAsync(() async {
    final screenshot = await boundary.toImage(pixelRatio: 2);
    final bytes = await screenshot.toByteData(format: ui.ImageByteFormat.png);
    final directory = Directory('build/expressive-screenshots')
      ..createSync(recursive: true);
    File('${directory.path}/$name.png')
        .writeAsBytesSync(bytes!.buffer.asUint8List());
    screenshot.dispose();
  });
}
