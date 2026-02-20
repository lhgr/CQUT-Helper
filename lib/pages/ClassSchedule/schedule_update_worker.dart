import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'controllers/schedule_controller.dart';
import '../../utils/local_notifications.dart';

const String _kPrefsKeyScheduleUpdateEnabled = 'schedule_update_enabled';
const String _kPrefsKeyScheduleUpdateIntervalMinutes =
    'schedule_update_interval_minutes';
const String _kPrefsKeyScheduleUpdateSystemNotifyEnabled =
    'schedule_update_system_notification_enabled';

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

    final interval =
        prefs.getInt(_kPrefsKeyScheduleUpdateIntervalMinutes) ?? 60;
    final freqMinutes = interval < 15 ? 15 : interval;

    await Workmanager().registerPeriodicTask(
      _uniqueName,
      _taskName,
      frequency: Duration(minutes: freqMinutes),
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

    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_kPrefsKeyScheduleUpdateEnabled) ?? false;
    if (!enabled) return true;

    final userId = prefs.getString('account');
    if (userId == null || userId.trim().isEmpty) return true;

    final controller = ScheduleController();
    final cached = await controller.loadFromCache();
    if (cached == null) return true;

    final weeksAhead = prefs.getInt('schedule_update_weeks_ahead') ?? 1;
    final changes = await controller.silentCheckRecentWeeksForChangesDetailed(
      cached,
      weeksAhead: weeksAhead,
    );
    if (changes.isEmpty) return true;

    final systemNotify =
        prefs.getBool(_kPrefsKeyScheduleUpdateSystemNotifyEnabled) ?? false;
    if (systemNotify) {
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

    final payload = <String, dynamic>{
      'createdAt': DateTime.now().millisecondsSinceEpoch,
      'yearTerm': cached.yearTerm,
      'changes': changes
          .map((c) => <String, dynamic>{'weekNum': c.weekNum, 'lines': c.lines})
          .toList(),
    };

    await prefs.setString(
      ScheduleUpdateWorker.pendingKeyForUser(userId),
      json.encode(payload),
    );

    return true;
  });
}
