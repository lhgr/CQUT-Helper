import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/utils/course_reminder_mode.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notificationsChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final pending = <int, Map<String, Object?>>{};
  final notificationCalls = <MethodCall>[];
  final scheduledDates = <DateTime>[];
  late String rawSchedule;
  bool permission = true;
  bool launchFromCourse = false;
  int? failSchedulingAt;
  Completer<void>? schedulingGate;
  Completer<void>? schedulingStarted;
  int secureReads = 0;

  setUpAll(() {
    databaseFactoryOrNull = databaseFactorySqflitePlugin;
  });

  setUp(() {
    pending.clear();
    notificationCalls.clear();
    scheduledDates.clear();
    permission = true;
    launchFromCourse = false;
    failSchedulingAt = null;
    schedulingGate = schedulingStarted = null;
    secureReads = 0;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    LocalNotifications.debugIsIOSOverride = true;
    LocalNotifications.debugIsAndroidOverride = false;
    CourseReminderMode.debugIsAndroidOverride = false;
    ScheduleUpdateWorker.debugIsAndroidOverride = false;
    FlutterLocalNotificationsPlatform.instance =
        IOSFlutterLocalNotificationsPlugin();
    LocalNotifications.debugResetInitialization();
    final tomorrow = DateTime.now().toUtc().add(
      const Duration(hours: 8, days: 1),
    );
    final date =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    rawSchedule = jsonEncode({
      'yearTerm': '2026-2027-1',
      'weekNum': '1',
      'weekList': ['1'],
      'weekDayList': [
        {'weekDay': '1', 'weekDate': date},
      ],
      'eventList': List.generate(
        80,
        (index) => {
          'eventID': 'course-$index',
          'eventName': 'course-$index',
          'weekDay': '1',
          'sessionStart': '1',
          'sessionLast': '1',
          'reminderMinutes': index + 1,
        },
      ),
    });
    SharedPreferences.setMockInitialValues({
      'account': 'ios-student',
      ScheduleSettingsManager.remindersEnabledKey: true,
      'schedule_time_info_cache_v1': jsonEncode({
        'items': [
          {'sessionNum': 1, 'startTime': '08:00', 'endTime': '08:45'},
        ],
      }),
    });
    messenger.setMockMethodCallHandler(notificationsChannel, (call) async {
      notificationCalls.add(call);
      final args = call.arguments is Map ? call.arguments as Map : null;
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {
            'notificationLaunchedApp': launchFromCourse,
            if (launchFromCourse)
              'notificationResponse': {
                'notificationId': 17,
                'notificationResponseType': 0,
                'payload': 'course_reminder|id|课程',
              },
          };
        case 'checkPermissions':
          return {'isEnabled': permission};
        case 'requestPermissions':
          permission = true;
          return true;
        case 'openAppNotificationSettings':
          return true;
        case 'pendingNotificationRequests':
          return pending.values.toList();
        case 'zonedSchedule':
          scheduledDates.add(
            DateTime.parse(args!['scheduledDateTimeISO8601'] as String),
          );
          if (scheduledDates.length == failSchedulingAt) {
            throw PlatformException(code: 'schedule_failed');
          }
          pending[args['id'] as int] = {
            'id': args['id'],
            'payload': args['payload'],
          };
          if (schedulingGate != null) {
            schedulingStarted?.complete();
            await schedulingGate!.future;
            schedulingGate = null;
          }
          return null;
        case 'cancel':
          pending.remove(call.arguments is int ? call.arguments : args!['id']);
          return null;
        case 'cancelAll':
          pending.clear();
          return null;
      }
      return null;
    });
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
            if (sql.contains('schedule_weeks')) {
              return [
                {
                  'user_id': 'ios-student',
                  'year_term': '2026-2027-1',
                  'week_num': '1',
                  'raw_json': rawSchedule,
                  'checksum': ScheduleCacheDatabase.checksumFor(rawSchedule),
                  'data_version': 1,
                  'fetched_at': DateTime.now().millisecondsSinceEpoch,
                  'last_verified_at': DateTime.now().millisecondsSinceEpoch,
                },
              ];
            }
            return <Map<String, Object?>>[];
          case 'execute':
            if ((args?['sql'] as String? ?? '').startsWith('BEGIN')) {
              return {'transactionId': 1};
            }
            return null;
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (_) async {
        secureReads++;
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel(
        'be.tramckrijte.workmanager/foreground_channel_work_manager',
      ),
      (call) async {
        fail('iOS must not invoke Workmanager.${call.method}');
      },
    );
  });

  tearDown(() async {
    await CourseReminderScheduler.cancelAll();
    LocalNotifications.debugResetInitialization();
    LocalNotifications.debugIsIOSOverride = null;
    LocalNotifications.debugIsAndroidOverride = null;
    CourseReminderMode.debugIsAndroidOverride = null;
    ScheduleUpdateWorker.debugIsAndroidOverride = null;
    debugDefaultTargetPlatformOverride = null;
    for (final channel in [
      notificationsChannel,
      const MethodChannel('com.tekartik.sqflite'),
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      const MethodChannel(
        'be.tramckrijte.workmanager/foreground_channel_work_manager',
      ),
    ]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('iOS startup checks permissions without prompting and cold launch consumes course payload', () async {
    launchFromCourse = true;
    permission = false;
    await LocalNotifications.initialize();
    final settings = notificationCalls.first.arguments as Map;
    expect(settings['requestAlertPermission'], isFalse);
    expect(settings['requestSoundPermission'], isFalse);
    expect(settings['requestBadgePermission'], isFalse);
    expect(
      notificationCalls.where((call) => call.method == 'requestPermissions'),
      isEmpty,
    );
    expect(await LocalNotifications.consumeOpenCourseReminderFlag(), isTrue);
    expect(await LocalNotifications.consumeOpenCourseReminderFlag(), isFalse);
    expect((await CourseReminderMode.getStatus()).notificationGranted, isFalse);
    expect(await LocalNotifications.ensureCourseReminderPermissions(), isTrue);
    expect(await CourseReminderMode.openSettings('notifications'), isTrue);
    expect(
      notificationCalls.any((call) => call.method.contains('Exact')),
      isFalse,
    );
  });

  test('iOS reserves other pending slots, keeps nearest notifications and recomputes capacity', () async {
    pending[1] = {'id': 1, 'payload': 'other'};
    pending[2] = {'id': 2, 'payload': 'other'};
    await CourseReminderScheduler.rescheduleForUser('ios-student');
    final first = await CourseReminderScheduler.loadStatus();
    expect(pending, hasLength(64));
    expect(first.scheduledCount, 62);
    expect(first.pendingLimitReached, isTrue);
    expect(first.ready, isTrue);
    expect(first.nextReminderAt, scheduledDates.first.toLocal());
    expect(first.coveredUntil, scheduledDates.last.toLocal());
    expect(scheduledDates, orderedEquals(scheduledDates.toList()..sort()));
    final prefs = await SharedPreferences.getInstance();
    final data = jsonDecode(rawSchedule) as Map<String, dynamic>;
    data['eventList'] = (data['eventList'] as List).take(10).toList();
    rawSchedule = jsonEncode(data);
    pending.remove(1);
    pending.remove(2);
    await CourseReminderScheduler.rescheduleForUser('ios-student');
    final replenished = await CourseReminderScheduler.loadStatus();
    expect(replenished.scheduledCount, 10);
    expect(replenished.pendingLimitReached, isFalse);
    expect(pending, hasLength(10));
    expect(
      (jsonDecode(prefs.getString('schedule_course_reminder_ids_v1')!) as List),
      hasLength(10),
    );
  });

  test('iOS capacity exhausted by other notifications reports zero available reminders', () async {
    for (var id = 0; id < 64; id++) {
      pending[id] = {'id': id, 'payload': 'other'};
    }
    await CourseReminderScheduler.rescheduleForUser('ios-student');
    final status = await CourseReminderScheduler.loadStatus();
    expect(pending, hasLength(64));
    expect(status.scheduledCount, 0);
    expect(status.ready, isFalse);
    expect(status.pendingLimitReached, isTrue);
    expect(status.coveredUntil, isNull);
    expect(status.reason, contains('上限'));
  });

  test('partial iOS scheduling failure cancels newly created reminders and invalidates success status', () async {
    failSchedulingAt = 3;
    await expectLater(
      CourseReminderScheduler.rescheduleForUser('ios-student'),
      throwsA(isA<PlatformException>()),
    );
    expect(pending, isEmpty);
    final status = await CourseReminderScheduler.loadStatus();
    expect(status.ready, isFalse);
    expect(status.scheduledCount, 0);
    expect(status.reason, contains('失败'));
  });

  test(
    'logout cancellation invalidates active and queued iOS rebuilds',
    () async {
      schedulingGate = Completer<void>();
      schedulingStarted = Completer<void>();
      final rebuilding = CourseReminderScheduler.rescheduleForUser(
        'ios-student',
      );
      await schedulingStarted!.future;
      final queued = CourseReminderScheduler.rescheduleForUser('ios-student');
      final cancelling = CourseReminderScheduler.cancelAll();
      schedulingGate!.complete();
      await Future.wait([rebuilding, queued, cancelling]);
      expect(pending, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('account');
      await CourseReminderScheduler.rescheduleForUser('ios-student');
      expect(pending, isEmpty);
      expect((await CourseReminderScheduler.loadStatus()).enabled, isFalse);
    },
  );

  test('iOS foreground calls coalesce, skip unconsented notices and avoid Workmanager', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ScheduleSettingsManager.remindersEnabledKey, false);
    await ScheduleUpdateWorker.initialize();
    await Future.wait(
      List.generate(3, (_) => ScheduleUpdateWorker.syncFromPreferences()),
    );
    expect(secureReads, 1);
    expect(
      notificationCalls.any((call) => call.method == 'requestPermissions'),
      isFalse,
    );
    await prefs.remove('account');
    await ScheduleUpdateWorker.syncFromPreferences();
    expect(pending, isEmpty);
  });
}
