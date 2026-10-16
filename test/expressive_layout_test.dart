import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_app_bar.dart';
import 'package:cqut_helper/pages/Mine/Mine.dart';
import 'package:cqut_helper/pages/Main/Main.dart';
import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
import 'package:cqut_helper/pages/Settings/schedule_layout_preview.dart';
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
late WorkmanagerPlatform _originalWorkmanager;
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
            if (sql.contains('schedule_weeks')) return [_scheduleRow];
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

  for (final compact in [false, true]) {
    final label = compact ? 'dark-320-large' : 'light-390';
    final brightness = compact ? Brightness.dark : Brightness.light;
    final width = compact ? 320.0 : 390.0;
    final scale = compact ? 1.6 : 1.0;

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

    testWidgets('schedule $label preserves the dense course layout', (
      tester,
    ) async {
      await _pumpPage(
        tester,
        Scaffold(
          appBar: ScheduleAppBar(
            loading: false,
            weekList: const ['7'],
            currentWeekIndex: 0,
            currentScheduleData: ScheduleData(yearTerm: _term),
            onRefresh: () {},
            onSettings: () {},
            onWeekPicker: () {},
            onTermPicker: () {},
          ),
          body: const ScheduleLayoutPreview(
            settings: ScheduleLayoutSettings(),
            showWeekend: false,
            timeInfoEnabled: true,
          ),
        ),
        width,
        brightness,
        scale,
      );
      expect(find.byType(ScheduleLayoutPreview), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _capturePage(tester, 'schedule-$label');
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
    });
  }
}

Future<void> _pumpPage(
  WidgetTester tester,
  Widget page,
  double width,
  Brightness brightness,
  double scale,
) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
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
  await tester.pumpWidget(
    RepaintBoundary(
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
        home: page,
      ),
    ),
  );
  if (_capture) {
    await tester.runAsync(() async {
      await precacheImage(
        const AssetImage('lib/assets/Icon.png'),
        tester.element(find.byKey(_captureKey)),
      );
    });
  }
  await tester.pumpAndSettle();
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
