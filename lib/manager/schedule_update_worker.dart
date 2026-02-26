import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:cqut/pages/ClassSchedule/controllers/schedule_controller.dart';
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
    if (backgroundRestricted == true) {
      nextMinutes = nextMinutes < 360 ? 360 : nextMinutes;
    }
    if (powerSave == true || (batteryLevel != null && batteryLevel <= 20)) {
      nextMinutes = nextMinutes * 3;
    }
    if (!activeRecently) {
      nextMinutes = nextMinutes * 2;
      if (nextMinutes < 120) nextMinutes = 120;
    }
    if (lowRam == true) nextMinutes = nextMinutes * 2;
    if (nextMinutes < 15) nextMinutes = 15;
    if (nextMinutes > 24 * 60) nextMinutes = 24 * 60;

    final controller = ScheduleController();
    final cached = await controller.loadFromCache();
    if (cached == null) {
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
    final weeksAhead = (prefs.getInt('schedule_update_weeks_ahead') ?? 1).clamp(
      0,
      maxWeeksAhead,
    );

    final expectedWeeks = 1 + weeksAhead;
    final changes = await controller.silentCheckRecentWeeksForChangesDetailed(
      cached,
      weeksAhead: weeksAhead,
    );
    final fetchedAt = DateTime.now().millisecondsSinceEpoch;

    final systemNotify =
        prefs.getBool(_kPrefsKeyScheduleUpdateSystemNotifyEnabled) ?? false;
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
      'linesBytes': bytes,
      'durationMs': durationMs,
      'unmetered': unmetered,
      'batteryLevel': batteryLevel,
      'powerSave': powerSave,
      'backgroundRestricted': backgroundRestricted,
      'activeRecently': activeRecently,
      'intervalBaseMin': baseMinutes,
      'intervalNextMin': nextMinutes,
    });

    await Workmanager().registerOneOffTask(
      ScheduleUpdateWorker._uniqueName,
      ScheduleUpdateWorker._taskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      initialDelay: Duration(minutes: nextMinutes),
    );

    return true;
  });
}
