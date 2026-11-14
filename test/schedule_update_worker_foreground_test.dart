import 'dart:async';
import 'dart:convert';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _term = '2026-2027-1';

class _ForegroundApi extends ScheduleApi {
  _ForegroundApi(this.onFetch);
  final Future<void> Function(String userId) onFetch;

  @override
  Future<ScheduleData> loadFromNetwork({
    required String userId,
    required String encryptedPassword,
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
    bool notifyWidget = true,
    bool refreshReminders = true,
    bool waitForSideEffects = true,
    String? refreshId,
  }) async {
    expect(notifyWidget, isFalse);
    await onFetch(userId);
    return ScheduleData(yearTerm: _term, weekNum: '2', weekList: ['2']);
  }

  @override
  Future<void> refreshCourseReminders(String userId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  const notificationChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final snapshots = <Map<String, dynamic>>[];

  Future<void> writeProjection(String userId, String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('schedule_widget_term_$userId', _term);
    await prefs.setString('schedule_widget_week_$userId', '2');
    await prefs.setString(
      'schedule_widget_calendar_projection_v1_$userId',
      jsonEncode({
        'schema_version': 1,
        'year_term': _term,
        'days': [
          {
            'date': '2026-09-29',
            'kind': 'normal',
            'events': [
              {'eventName': name},
            ],
          },
        ],
      }),
    );
    await ScheduleRefreshState.markSuccess(userId);
  }

  setUp(() {
    ScheduleUpdateWorker.debugResetForegroundState();
    ScheduleUpdateWorker.debugIsAndroidOverride = false;
    LocalNotifications.debugIsAndroidOverride = false;
    LocalNotifications.debugIsIOSOverride = true;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    FlutterLocalNotificationsPlatform.instance =
        IOSFlutterLocalNotificationsPlugin();
    LocalNotifications.debugResetInitialization();
    WidgetUpdater.debugIsAndroidOverride = false;
    WidgetUpdater.debugIsIOSOverride = true;
    snapshots.clear();
    SharedPreferences.setMockInitialValues({
      'account': 'student',
      'schedule_widget_term_student': _term,
      'schedule_widget_week_student': '2',
      'academic_calendar_snapshot_v1_$_term': jsonEncode({
        'schema_version': 1,
        'year_term': _term,
        'revision': 'unchanged',
        'generated_at': DateTime.now().toIso8601String(),
        'term_calendar_complete': true,
        'days': [],
      }),
      'academic_calendar_checked_at_v1_$_term':
          DateTime.now().millisecondsSinceEpoch,
    });
    messenger.setMockMethodCallHandler(secureChannel, (_) async => 'password');
    messenger.setMockMethodCallHandler(notificationChannel, (call) async {
      if (call.method == 'pendingNotificationRequests') return <Object>[];
      if (call.method == 'initialize') return true;
      return null;
    });
    WidgetUpdater.debugMethodInvoker = (_, arguments) async {
      expect(arguments['trigger'], 'foreground_sync_complete');
      snapshots.add(
        jsonDecode(arguments['snapshotJson']! as String)
            as Map<String, dynamic>,
      );
    };
  });

  tearDown(() {
    ScheduleUpdateWorker.debugResetForegroundState();
    ScheduleUpdateWorker.debugIsAndroidOverride = null;
    LocalNotifications.debugIsAndroidOverride = null;
    LocalNotifications.debugIsIOSOverride = null;
    debugDefaultTargetPlatformOverride = null;
    LocalNotifications.debugResetInitialization();
    WidgetUpdater.resetDebugOverrides();
    messenger.setMockMethodCallHandler(secureChannel, null);
    messenger.setMockMethodCallHandler(notificationChannel, null);
  });

  test('foreground completion publishes fresh classes without notice enhancement or calendar changes', () async {
    await writeProjection('student', '旧课程');
    ScheduleUpdateWorker.debugForegroundScheduleApiFactory = () =>
        _ForegroundApi((userId) => writeProjection(userId, '同步后的课程'));
    await ScheduleUpdateWorker.syncFromPreferences();
    expect(snapshots, hasLength(1));
    expect(snapshots.single['activeUserId'], 'student');
    expect(
      snapshots
          .single['calendarProjection']['days']
          .single['events']
          .single['eventName'],
      '同步后的课程',
    );
    expect(snapshots.single['refresh']['state'], 'normal');
  });

  test(
    'a failed foreground fetch still publishes the retained saved classes',
    () async {
      await writeProjection('student', '离线课程');
      ScheduleUpdateWorker.debugForegroundScheduleApiFactory = () =>
          _ForegroundApi((_) async => throw StateError('offline'));
      await ScheduleUpdateWorker.syncFromPreferences();
      expect(snapshots, hasLength(1));
      expect(
        snapshots
            .single['calendarProjection']['days']
            .single['events']
            .single['eventName'],
        '离线课程',
      );
    },
  );

  for (final nextAccount in ['', 'other', 'student']) {
    test(
      'an obsolete foreground generation cannot publish after transition to "$nextAccount"',
      () async {
        final started = Completer<void>();
        final release = Completer<void>();
        ScheduleUpdateWorker.debugForegroundScheduleApiFactory = () =>
            _ForegroundApi((userId) async {
              if (!started.isCompleted) {
                started.complete();
                await release.future;
              }
              await writeProjection(userId, '课程:$userId');
            });
        final first = ScheduleUpdateWorker.syncFromPreferences();
        await started.future;
        final prefs = await SharedPreferences.getInstance();
        // Logout invalidates A even when the user signs back into A immediately.
        await prefs.remove('account');
        await ScheduleUpdateWorker.syncFromPreferences();
        if (nextAccount.isNotEmpty) {
          await prefs.setString('account', nextAccount);
        }
        final next = nextAccount.isEmpty
            ? Future<void>.value()
            : ScheduleUpdateWorker.syncFromPreferences();
        release.complete();
        await Future.wait([first, next]);
        if (nextAccount.isEmpty) {
          expect(snapshots, isEmpty);
        } else {
          expect(snapshots, hasLength(1));
          expect(snapshots.single['activeUserId'], nextAccount);
          expect(
            snapshots
                .single['calendarProjection']['days']
                .single['events']
                .single['eventName'],
            '课程:$nextAccount',
          );
        }
      },
    );
  }
}
