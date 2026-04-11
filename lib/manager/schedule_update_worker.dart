import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:cqut/model/schedule_week_change.dart';
import 'package:cqut/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut/manager/course_reminder_manager.dart';
import 'package:cqut/utils/app_logger.dart';
import 'package:cqut/utils/local_notifications.dart';
import 'package:cqut/utils/android_background_restrictions.dart';
import 'package:cqut/utils/schedule_update_log.dart';
import 'package:cqut/utils/schedule_update_range_utils.dart';

const String _kPrefsKeyScheduleUpdateEnabled = 'schedule_update_enabled';
const String _kPrefsKeyScheduleUpdateIntervalMinutes =
    'schedule_update_interval_minutes';
const String _kPrefsKeyScheduleUpdateSystemNotifyEnabled =
    'schedule_update_system_notification_enabled';
const String _kPrefsKeyAppLastActiveAt = 'app_last_active_at';
const String _kPrefsKeyScheduleUpdateBgFailureStreak =
    'schedule_update_bg_failure_streak_v1';
const int _kScheduleUpdateBgFullScanIntervalMs = 12 * 60 * 60 * 1000;

String _bgFullScanAtKey(String userId, String yearTerm) =>
    'schedule_update_bg_full_scan_at_${userId}_$yearTerm';

class ScheduleUpdateWorker {
  static const String _prefsKeyPendingPrefix = 'schedule_pending_changes_';

  static const String _taskName = 'schedule_update_check';
  static const String _uniqueName = 'schedule_update_periodic';

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    if (_initialized) return;
    await Workmanager().initialize(callbackDispatcher);
    _initialized = true;
  }

  static Future<void> syncFromPreferences() async {
    if (!Platform.isAndroid) return;
    await initialize();

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kPrefsKeyScheduleUpdateEnabled) ?? false;
    if (!enabled) {
      await Workmanager().cancelByUniqueName(_uniqueName);
      return;
    }

    await Workmanager().registerOneOffTask(
      _uniqueName,
      _taskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      initialDelay: Duration(minutes: 1),
    );
  }

  static String pendingKeyForUser(String userId) =>
      '$_prefsKeyPendingPrefix$userId';
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    final startAt = DateTime.now();
    final logDate = startAt.toIso8601String().split('T').first;
    await AppLogger.I.init(
      minLevel: LogLevel.info,
      enableConsole: false,
      enableFile: true,
      fileName: 'cqut_$logDate.log',
    );
    AppLogger.I.info('ScheduleUpdate', 'background_task_start');
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kPrefsKeyScheduleUpdateEnabled) ?? false;
    if (!enabled) return true;

    final userId = prefs.getString('account');
    if (userId == null || userId.trim().isEmpty) return true;

    final interval =
        prefs.getInt(_kPrefsKeyScheduleUpdateIntervalMinutes) ?? 60;
    final baseMinutes = interval < 15 ? 15 : interval;
    final lastActiveAt = prefs.getInt(_kPrefsKeyAppLastActiveAt) ?? 0;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final activeRecently =
        lastActiveAt > 0 && nowMs - lastActiveAt <= 2 * 60 * 60 * 1000;

    final batteryLevel = await AndroidBackgroundRestrictions.batteryLevel();
    final powerSave = await AndroidBackgroundRestrictions.isPowerSaveMode();
    final backgroundRestricted =
        await AndroidBackgroundRestrictions.isBackgroundRestricted();
    final lowRam = await AndroidBackgroundRestrictions.isLowRamDevice();
    final unmetered = await AndroidBackgroundRestrictions.isUnmeteredNetwork();

    int nextMinutes = baseMinutes;
    final reasons = <String>[];
    if (backgroundRestricted == true) {
      nextMinutes = nextMinutes < 360 ? 360 : nextMinutes;
      reasons.add('backgroundRestricted');
    }
    if (powerSave == true || (batteryLevel != null && batteryLevel <= 20)) {
      nextMinutes = nextMinutes * 3;
      reasons.add('powerSaveOrLowBattery');
    }
    if (!activeRecently) {
      nextMinutes = nextMinutes * 2;
      if (nextMinutes < 120) nextMinutes = 120;
      reasons.add('inactiveRecently');
    }
    if (lowRam == true) {
      nextMinutes = nextMinutes * 2;
      reasons.add('lowRamDevice');
    }
    if (nextMinutes < 15) nextMinutes = 15;
    if (nextMinutes > 24 * 60) nextMinutes = 24 * 60;

    final controller = ScheduleController();
    final cached = await controller.loadFromCache();
    if (cached == null) {
      await ScheduleUpdateLog.appendRun({
        'at': DateTime.now().millisecondsSinceEpoch,
        'type': 'background_no_cache',
        'intervalBaseMin': baseMinutes,
        'intervalNextMin': nextMinutes,
        'reasons': reasons,
        'unmetered': unmetered,
        'batteryLevel': batteryLevel,
        'powerSave': powerSave,
        'backgroundRestricted': backgroundRestricted,
        'activeRecently': activeRecently,
      });
      AppLogger.I.info(
        'ScheduleUpdate',
        'background_task_schedule',
        fields: {
          'nextMinutes': nextMinutes,
          'reasons': reasons,
          'note': 'no_cache',
        },
      );
      await Workmanager().registerOneOffTask(
        ScheduleUpdateWorker._uniqueName,
        ScheduleUpdateWorker._taskName,
        existingWorkPolicy: ExistingWorkPolicy.replace,
        constraints: Constraints(networkType: NetworkType.connected),
        initialDelay: Duration(minutes: nextMinutes),
      );
      return true;
    }

    final maxWeeksAhead = maxWeeksAheadForSchedule(
      weekList: cached.weekList,
      currentWeek: cached.weekNum,
    );
    final configuredWeeksAhead =
        (prefs.getInt('schedule_update_weeks_ahead') ?? 1).clamp(
          0,
          maxWeeksAhead,
        );
    final systemNotify =
        prefs.getBool(_kPrefsKeyScheduleUpdateSystemNotifyEnabled) ?? false;

    int weeksAhead = configuredWeeksAhead;
    if ((systemNotify || unmetered == true) &&
        maxWeeksAhead > configuredWeeksAhead) {
      final term = cached.yearTerm ?? '';
      if (term.isNotEmpty) {
        final key = _bgFullScanAtKey(userId, term);
        final last = prefs.getInt(key) ?? 0;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (last <= 0 || now - last >= _kScheduleUpdateBgFullScanIntervalMs) {
          weeksAhead = maxWeeksAhead;
          await prefs.setInt(key, now);
          reasons.add('fullScan');
        }
      }
    }

    final expectedWeeks = 1 + weeksAhead;
    final failuresBefore = await ScheduleUpdateLog.failureCounter();
    List<ScheduleWeekChange> changes = const <ScheduleWeekChange>[];
    Object? runError;
    StackTrace? runStack;
    try {
      changes = await controller.silentCheckRecentWeeksForChangesDetailed(
        cached,
        weeksAhead: weeksAhead,
      );
    } catch (e, st) {
      runError = e;
      runStack = st;
      await ScheduleUpdateLog.appendFailure({
        'at': DateTime.now().millisecondsSinceEpoch,
        'scope': 'background_task',
        'error': e.toString(),
      });
    }
    final fetchedAt = DateTime.now().millisecondsSinceEpoch;
    final failuresAfter = await ScheduleUpdateLog.failureCounter();
    final failureDelta = failuresAfter - failuresBefore;
    final hadFailures = runError != null || failureDelta > 0;
    if (hadFailures) {
      final streak =
          (prefs.getInt(_kPrefsKeyScheduleUpdateBgFailureStreak) ?? 0) + 1;
      await prefs.setInt(_kPrefsKeyScheduleUpdateBgFailureStreak, streak);
      int retryMinutes = 15;
      for (int i = 1; i < streak && retryMinutes < nextMinutes; i++) {
        retryMinutes = retryMinutes * 2;
      }
      if (retryMinutes < nextMinutes) {
        nextMinutes = retryMinutes;
        reasons.add('failureRetry');
        reasons.add('failureStreak=$streak');
      } else {
        reasons.add('failureStreak=$streak');
      }
    } else {
      await prefs.setInt(_kPrefsKeyScheduleUpdateBgFailureStreak, 0);
    }
    if (runStack != null) {
      AppLogger.I.warn(
        'ScheduleUpdate',
        'background_task_exception',
        error: runError,
        stackTrace: runStack,
      );
    }

    if (systemNotify && changes.isNotEmpty) {
      final first = changes.first;
      final week = first.weekNum;
      String labelForWeek() {
        final currentWeek = cached.weekNum;
        final wList = cached.weekList;
        if (currentWeek != null && week == currentWeek) return '本周';
        if (wList != null && currentWeek != null) {
          final idx = wList.indexOf(week);
          final cIdx = wList.indexOf(currentWeek);
          if (idx != -1 && cIdx != -1 && idx == cIdx + 1) return '下周';
        }
        return '第$week周';
      }

      final brief = first.lines.isNotEmpty ? '：${first.brief}' : '';
      await LocalNotifications.showScheduleUpdate(
        title: '课表更新提醒',
        body: '${labelForWeek()}课表有更新$brief\n点击查看详情',
        payload: LocalNotifications.payloadScheduleUpdate,
      );
    }

    if (changes.isNotEmpty) {
      final payload = <String, dynamic>{
        'createdAt': fetchedAt,
        'yearTerm': cached.yearTerm,
        'changes': changes
            .map(
              (c) => <String, dynamic>{'weekNum': c.weekNum, 'lines': c.lines},
            )
            .toList(),
      };

      await prefs.setString(
        ScheduleUpdateWorker.pendingKeyForUser(userId),
        json.encode(payload),
      );
    }

    final durationMs = DateTime.now().difference(startAt).inMilliseconds;
    int bytes = 0;
    for (final c in changes) {
      for (final l in c.lines) {
        bytes += l.length;
      }
    }

    await ScheduleUpdateLog.appendRun({
      'at': fetchedAt,
      'type': 'background',
      'weeksPlanned': expectedWeeks,
      'weeksChanged': changes.length,
      'hadFailures': hadFailures,
      'failureDelta': failureDelta,
      'linesBytes': bytes,
      'durationMs': durationMs,
      'unmetered': unmetered,
      'batteryLevel': batteryLevel,
      'powerSave': powerSave,
      'backgroundRestricted': backgroundRestricted,
      'activeRecently': activeRecently,
      'intervalBaseMin': baseMinutes,
      'intervalNextMin': nextMinutes,
      'reasons': reasons,
    });

    AppLogger.I.info(
      'ScheduleUpdate',
      'background_task_schedule',
      fields: {
        'nextMinutes': nextMinutes,
        'reasons': reasons,
        'hadFailures': hadFailures,
        'weeksChanged': changes.length,
      },
    );
    await Workmanager().registerOneOffTask(
      ScheduleUpdateWorker._uniqueName,
      ScheduleUpdateWorker._taskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      initialDelay: Duration(minutes: nextMinutes),
    );

    await CourseReminderManager.sync();
    AppLogger.I.info(
      'ScheduleUpdate',
      'background_task_end',
      fields: {
        'hadFailures': hadFailures,
        'weeksChanged': changes.length,
        'nextMinutes': nextMinutes,
      },
    );
    return true;
  });
}
