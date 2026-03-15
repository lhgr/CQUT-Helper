import 'dart:convert';
import 'package:cqut/api/schedule/schedule_api.dart';
import 'package:cqut/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/model/schedule_week_change.dart';
import 'package:cqut/utils/local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

class ScheduleUpdateWorker {
  static const String _taskName = 'schedule_notice_poll_task';
  static const int _frequencyMinutes = 30;

  static String pendingKeyForUser(String userId) => 'schedule_pending_changes_$userId';

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> syncFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    final encryptedPassword = (prefs.getString('encrypted_password') ?? '').trim();
    final enabled = prefs.getBool('schedule_background_polling_enabled') ?? false;
    if (!enabled || userId.isEmpty || encryptedPassword.isEmpty) {
      await Workmanager().cancelByUniqueName(_taskName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: _frequencyMinutes),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(
        networkType: NetworkType.connected,
      ),
      inputData: {
        'userId': userId,
        'encryptedPassword': encryptedPassword,
      },
    );
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      WidgetsFlutterBinding.ensureInitialized();
      if (task != _taskName) return true;
      if (_isDeepNight()) return true;
      final userId = ((inputData?['userId'] ?? '').toString()).trim();
      final encryptedPassword =
          ((inputData?['encryptedPassword'] ?? '').toString()).trim();
      if (userId.isEmpty || encryptedPassword.isEmpty) {
        return true;
      }
      final prefs = await SharedPreferences.getInstance();
      final currentAccount = (prefs.getString('account') ?? '').trim();
      final currentPassword = (prefs.getString('encrypted_password') ?? '').trim();
      if (currentAccount.isEmpty || currentPassword.isEmpty) {
        await prefs.setString('account', userId);
        await prefs.setString('encrypted_password', encryptedPassword);
      }

      final scheduleApi = ScheduleApi();
      ScheduleData? currentData;
      try {
        currentData = await scheduleApi.loadFromCache(userId: userId);
      } catch (_) {}
      if (currentData == null) {
        try {
          currentData = await scheduleApi.loadFromNetwork(
            userId: userId,
            encryptedPassword: encryptedPassword,
            persistLastViewed: false,
            updateWidgetPins: false,
          );
        } catch (_) {
          return true;
        }
      }
      if (currentData.yearTerm == null ||
          currentData.yearTerm!.trim().isEmpty ||
          currentData.weekList == null ||
          currentData.weekList!.isEmpty) {
        return true;
      }

      final pipeline = ScheduleNoticeRefreshPipeline(
        refreshWeek: (weekNum, yearTerm) async {
          final raw = await scheduleApi.fetchRawWeekEvents(
            userId: userId,
            encryptedPassword: encryptedPassword,
            weekNum: weekNum,
            yearTerm: yearTerm,
          );
          await scheduleApi.saveScheduleJson(
            userId: userId,
            yearTerm: yearTerm,
            weekNum: weekNum,
            jsonStr: json.encode(raw),
          );
        },
      );

      ScheduleNoticeRefreshResult result;
      try {
        result = await pipeline.run(
          currentData: currentData,
          headless: true,
        );
      } catch (_) {
        return true;
      }

      if (result.apiClosed || result.changes.isEmpty) return true;

      await _writePendingChanges(
        prefs: prefs,
        userId: userId,
        yearTerm: currentData.yearTerm!.trim(),
        changes: result.changes,
      );
      final title = '课表更新提醒';
      final body = '检测到 ${result.changes.length} 周存在调课变更';
      await LocalNotifications.showScheduleUpdate(
        title: title,
        body: body,
        payload: LocalNotifications.payloadScheduleUpdate,
      );
      return true;
    });
  }

  static bool _isDeepNight() {
    final hour = DateTime.now().hour;
    return hour >= 0 && hour < 7;
  }

  static Future<void> _writePendingChanges({
    required SharedPreferences prefs,
    required String userId,
    required String yearTerm,
    required List<ScheduleWeekChange> changes,
  }) async {
    final payload = json.encode({
      'yearTerm': yearTerm,
      'changes': changes
          .map(
            (e) => {
              'weekNum': e.weekNum,
              'lines': e.lines,
            },
          )
          .toList(),
    });
    await prefs.setString(pendingKeyForUser(userId), payload);
  }
}
