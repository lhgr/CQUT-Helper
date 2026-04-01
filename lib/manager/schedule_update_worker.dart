import 'dart:convert';
import 'package:cqut/api/schedule/schedule_api.dart';
import 'package:cqut/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/model/schedule_week_change.dart';
import 'package:cqut/utils/app_logger.dart';
import 'package:cqut/utils/local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

class ScheduleUpdateWorker {
  static const String _taskName = 'schedule_notice_poll_task';
  static const String _immediateTaskUniqueName =
      'schedule_notice_poll_task_immediate';
  static const int _frequencyMinutes = 30;
  static bool _loggerReady = false;

  static String pendingKeyForUser(String userId) =>
      'schedule_pending_changes_$userId';

  static Future<void> initialize() async {
    await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  }

  static Future<void> syncFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    final encryptedPassword = (prefs.getString('encrypted_password') ?? '')
        .trim();
    final enabled =
        prefs.getBool('schedule_background_polling_enabled') ?? false;
    if (!enabled || userId.isEmpty || encryptedPassword.isEmpty) {
      await Workmanager().cancelByUniqueName(_taskName);
      await Workmanager().cancelByUniqueName(_immediateTaskUniqueName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      _taskName,
      _taskName,
      frequency: const Duration(minutes: _frequencyMinutes),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {
        'userId': userId,
        'encryptedPassword': encryptedPassword,
        'trigger': 'periodic',
      },
    );
    await Workmanager().registerOneOffTask(
      _immediateTaskUniqueName,
      _taskName,
      initialDelay: const Duration(minutes: 1),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      constraints: Constraints(networkType: NetworkType.connected),
      inputData: {
        'userId': userId,
        'encryptedPassword': encryptedPassword,
        'trigger': 'one_off',
      },
    );
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      WidgetsFlutterBinding.ensureInitialized();
      await _ensureLoggerReady();
      Future<bool> done() async {
        await AppLogger.I.flush();
        return true;
      }

      if (task != _taskName) {
        AppLogger.I.info(
          'ScheduleUpdateWorker',
          'skip unknown task',
          fields: {'task': task},
        );
        return done();
      }
      final trigger = ((inputData?['trigger'] ?? 'unknown').toString()).trim();
      AppLogger.I.info(
        'ScheduleUpdateWorker',
        'heartbeat task started',
        fields: {'task': task, 'trigger': trigger},
      );
      if (_isDeepNight()) {
        AppLogger.I.info(
          'ScheduleUpdateWorker',
          'skip deep night window',
          fields: {'trigger': trigger},
        );
        return done();
      }
      final userId = ((inputData?['userId'] ?? '').toString()).trim();
      final encryptedPassword =
          ((inputData?['encryptedPassword'] ?? '').toString()).trim();
      if (userId.isEmpty || encryptedPassword.isEmpty) {
        AppLogger.I.warn(
          'ScheduleUpdateWorker',
          'skip missing task credentials',
          fields: {'trigger': trigger},
        );
        return done();
      }
      final prefs = await SharedPreferences.getInstance();
      final currentAccount = (prefs.getString('account') ?? '').trim();
      final currentPassword = (prefs.getString('encrypted_password') ?? '')
          .trim();
      if (currentAccount.isEmpty || currentPassword.isEmpty) {
        await prefs.setString('account', userId);
        await prefs.setString('encrypted_password', encryptedPassword);
      }

      final scheduleApi = ScheduleApi();
      ScheduleData? currentData;
      try {
        currentData = await scheduleApi.loadFromCache(userId: userId);
      } catch (e, st) {
        AppLogger.I.warn(
          'ScheduleUpdateWorker',
          'load cache failed',
          error: e,
          stackTrace: st,
          fields: {'trigger': trigger},
        );
      }
      if (currentData == null) {
        AppLogger.I.info(
          'ScheduleUpdateWorker',
          'cache miss fallback to network',
          fields: {'trigger': trigger},
        );
        try {
          currentData = await scheduleApi.loadFromNetwork(
            userId: userId,
            encryptedPassword: encryptedPassword,
            persistLastViewed: false,
            updateWidgetPins: false,
          );
        } catch (e, st) {
          AppLogger.I.warn(
            'ScheduleUpdateWorker',
            'load network failed',
            error: e,
            stackTrace: st,
            fields: {'trigger': trigger},
          );
          return done();
        }
      }
      if (currentData.yearTerm == null ||
          currentData.yearTerm!.trim().isEmpty ||
          currentData.weekList == null ||
          currentData.weekList!.isEmpty) {
        AppLogger.I.warn(
          'ScheduleUpdateWorker',
          'skip invalid schedule data',
          fields: {'trigger': trigger},
        );
        return done();
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
        result = await pipeline.run(currentData: currentData, headless: true);
      } catch (e, st) {
        AppLogger.I.warn(
          'ScheduleUpdateWorker',
          'pipeline run failed',
          error: e,
          stackTrace: st,
          fields: {'trigger': trigger},
        );
        return done();
      }

      if (result.apiClosed || result.changes.isEmpty) {
        AppLogger.I.info(
          'ScheduleUpdateWorker',
          'heartbeat task finished without changes',
          fields: {
            'trigger': trigger,
            'apiClosed': result.apiClosed,
            'changes': result.changes.length,
          },
        );
        return done();
      }

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
      AppLogger.I.info(
        'ScheduleUpdateWorker',
        'heartbeat task detected schedule changes',
        fields: {'trigger': trigger, 'changes': result.changes.length},
      );
      return done();
    });
  }

  static Future<void> _ensureLoggerReady() async {
    if (_loggerReady) return;
    try {
      final logDate = DateTime.now().toIso8601String().split('T').first;
      await AppLogger.I.init(
        minLevel: LogLevel.info,
        enableConsole: true,
        enableFile: true,
        fileName: 'cqut_$logDate.log',
      );
      _loggerReady = true;
    } catch (_) {}
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
          .map((e) => {'weekNum': e.weekNum, 'lines': e.lines})
          .toList(),
    });
    await prefs.setString(pendingKeyForUser(userId), payload);
  }
}
