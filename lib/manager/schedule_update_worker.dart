import 'dart:convert';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/manager/schedule_update_worker_health.dart';
import 'package:cqut_helper/manager/schedule_update_worker_state_store.dart';
import 'package:cqut_helper/manager/schedule_update_worker_target.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

export 'package:cqut_helper/manager/schedule_update_worker_health.dart';

@pragma('vm:entry-point')
void scheduleUpdateCallbackDispatcher() {
  ScheduleUpdateWorker.callbackDispatcher();
}

class ScheduleUpdateWorker {
  static const String _taskName = 'schedule_notice_poll_task';
  static const String _immediateTaskUniqueName =
      'schedule_notice_poll_task_immediate';
  static const int _frequencyMinutes = 60;
  static bool _loggerReady = false;

  static String pendingKeyForUser(String userId) =>
      scheduleUpdateWorkerPendingKeyForUser(userId);

  @visibleForTesting
  static ({String? yearTerm, String weekNum}) resolvePollingTarget({
    required SharedPreferences prefs,
    required String userId,
  }) {
    return resolveScheduleUpdateWorkerPollingTarget(
      prefs: prefs,
      userId: userId,
    );
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(
      scheduleUpdateCallbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> markEnabledAtIfNeeded({required bool enabled}) {
    return markScheduleUpdateWorkerEnabledAtIfNeeded(enabled: enabled);
  }

  static Future<ScheduleBackgroundPollHealthSnapshot> loadHealthSnapshot() {
    return loadScheduleUpdateWorkerHealthSnapshot(
      frequencyMinutes: _frequencyMinutes,
    );
  }

  static Future<void> syncFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    final encryptedPassword = (prefs.getString('encrypted_password') ?? '')
        .trim();
    final enabled =
        prefs.getBool('schedule_background_polling_enabled') ?? false;
    await recordScheduleUpdateWorkerSyncState(
      status: 'sync_start',
      fields: {
        'enabled': enabled,
        'hasUserId': userId.isNotEmpty,
        'hasPassword': encryptedPassword.isNotEmpty,
      },
    );
    if (!enabled || userId.isEmpty || encryptedPassword.isEmpty) {
      await Workmanager().cancelByUniqueName(_taskName);
      await Workmanager().cancelByUniqueName(_immediateTaskUniqueName);
      await recordScheduleUpdateWorkerSyncState(
        status: 'sync_cancelled',
        fields: {
          'enabled': enabled,
          'hasUserId': userId.isNotEmpty,
          'hasPassword': encryptedPassword.isNotEmpty,
        },
      );
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
    await recordScheduleUpdateWorkerSyncState(
      status: 'sync_registered',
      fields: {'frequencyMinutes': _frequencyMinutes},
    );
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      WidgetsFlutterBinding.ensureInitialized();
      await _ensureLoggerReady();
      final trigger = ((inputData?['trigger'] ?? 'unknown').toString()).trim();
      await recordScheduleUpdateWorkerState(
        status: 'started',
        trigger: trigger,
        task: task,
      );
      Future<bool> done({
        required String status,
        Map<String, Object?> fields = const {},
      }) async {
        await recordScheduleUpdateWorkerState(
          status: status,
          trigger: trigger,
          task: task,
          fields: fields,
        );
        await AppLogger.I.flush();
        return true;
      }

      if (task != _taskName) {
        AppLogger.I.event(
          LogLevel.warn,
          'ScheduleUpdateWorker',
          event: 'schedule_notice_poll_unknown_task',
          messageZh: '后台轮询跳过未知任务',
          message: 'skip unknown task',
          module: 'schedule_notice_poll',
          action: 'validate_task',
          status: 'skip',
          reason: 'unknown_task',
          fields: {'task': task},
        );
        return done(status: 'skip_unknown_task');
      }
      if (_isDeepNight()) {
        return done(status: 'skip_deep_night');
      }
      final userId = ((inputData?['userId'] ?? '').toString()).trim();
      final encryptedPassword =
          ((inputData?['encryptedPassword'] ?? '').toString()).trim();
      if (userId.isEmpty || encryptedPassword.isEmpty) {
        AppLogger.I.event(
          LogLevel.warn,
          'ScheduleUpdateWorker',
          event: 'schedule_notice_poll_missing_credentials',
          messageZh: '后台轮询跳过缺失凭证任务',
          message: 'skip missing task credentials',
          module: 'schedule_notice_poll',
          action: 'validate_credentials',
          status: 'skip',
          reason: 'missing_credentials',
          fields: {'trigger': trigger},
        );
        return done(status: 'skip_missing_credentials');
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
      final pollingTarget = resolvePollingTarget(prefs: prefs, userId: userId);
      final preferredTerm = (pollingTarget.yearTerm ?? '').trim();
      final preferredWeek = pollingTarget.weekNum.trim();
      try {
        if (preferredTerm.isNotEmpty) {
          currentData = await scheduleApi.loadFromCache(
            userId: userId,
            weekNum: preferredWeek,
            yearTerm: preferredTerm,
          );
        }
        currentData ??= await scheduleApi.loadFromCache(userId: userId);
      } catch (e, st) {
        AppLogger.I.event(
          LogLevel.warn,
          'ScheduleUpdateWorker',
          event: 'schedule_notice_poll_cache_load_fail',
          messageZh: '后台轮询读取缓存失败',
          message: 'load cache failed',
          module: 'schedule_notice_poll',
          action: 'load_cache',
          status: 'fail',
          reason: 'cache_read_failed',
          error: e,
          stackTrace: st,
          fields: {'trigger': trigger},
        );
      }
      if (currentData == null) {
        AppLogger.I.info(
          'ScheduleUpdateWorker',
          'cache miss fallback to network',
          fields: {
            'trigger': trigger,
            'preferredTerm': preferredTerm,
            'preferredWeek': preferredWeek,
          },
        );
        try {
          currentData = await scheduleApi.loadFromNetwork(
            userId: userId,
            encryptedPassword: encryptedPassword,
            weekNum: preferredWeek,
            yearTerm: preferredTerm.isEmpty ? null : preferredTerm,
            persistLastViewed: false,
            updateWidgetPins: false,
          );
        } catch (e, st) {
          AppLogger.I.event(
            LogLevel.error,
            'ScheduleUpdateWorker',
            event: 'schedule_notice_poll_network_load_fail',
            messageZh: '后台轮询拉取课表失败',
            message: 'load network failed',
            module: 'schedule_notice_poll',
            action: 'load_network',
            status: 'fail',
            reason: 'network_load_failed',
            error: e,
            stackTrace: st,
            fields: {
              'trigger': trigger,
              'preferredTerm': preferredTerm,
              'preferredWeek': preferredWeek,
            },
          );
          return done(
            status: 'load_network_failed',
            fields: {'error': e.toString()},
          );
        }
      }
      if (currentData.yearTerm == null ||
          currentData.yearTerm!.trim().isEmpty ||
          currentData.weekList == null ||
          currentData.weekList!.isEmpty) {
        AppLogger.I.event(
          LogLevel.warn,
          'ScheduleUpdateWorker',
          event: 'schedule_notice_poll_invalid_schedule_data',
          messageZh: '后台轮询跳过无效课表数据',
          message: 'skip invalid schedule data',
          module: 'schedule_notice_poll',
          action: 'validate_schedule',
          status: 'skip',
          reason: 'invalid_schedule_data',
          fields: {'trigger': trigger},
        );
        return done(status: 'skip_invalid_schedule_data');
      }
      if (preferredTerm.isNotEmpty &&
          currentData.yearTerm!.trim() != preferredTerm) {
        AppLogger.I.event(
          LogLevel.warn,
          'ScheduleUpdateWorker',
          event: 'schedule_notice_poll_term_mismatch',
          messageZh: '后台轮询跳过学期不匹配数据',
          message: 'polling term mismatch',
          module: 'schedule_notice_poll',
          action: 'validate_term',
          status: 'skip',
          reason: 'term_mismatch',
          fields: {
            'trigger': trigger,
            'preferredTerm': preferredTerm,
            'currentTerm': currentData.yearTerm!.trim(),
          },
        );
        return done(
          status: 'skip_term_mismatch',
          fields: {
            'preferredTerm': preferredTerm,
            'currentTerm': currentData.yearTerm!.trim(),
          },
        );
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
        AppLogger.I.event(
          LogLevel.error,
          'ScheduleUpdateWorker',
          event: 'schedule_notice_poll_pipeline_fail',
          messageZh: '后台轮询处理流程失败',
          message: 'pipeline run failed',
          module: 'schedule_notice_poll',
          action: 'run_pipeline',
          status: 'fail',
          reason: 'pipeline_failed',
          error: e,
          stackTrace: st,
          fields: {'trigger': trigger},
        );
        return done(status: 'pipeline_failed', fields: {'error': e.toString()});
      }

      if (result.apiClosed || result.changes.isEmpty) {
        await recordScheduleUpdateWorkerSuccessfulRun();
        return done(
          status: result.apiClosed ? 'api_closed' : 'no_changes',
          fields: {
            'apiClosed': result.apiClosed,
            'changes': result.changes.length,
          },
        );
      }

      await writeScheduleUpdateWorkerPendingChanges(
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
      await recordScheduleUpdateWorkerSuccessfulRun();
      AppLogger.I.info(
        'ScheduleUpdateWorker',
        'heartbeat task detected schedule changes',
        fields: {'trigger': trigger, 'changes': result.changes.length},
      );
      return done(
        status: 'changes_detected',
        fields: {'changes': result.changes.length},
      );
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
}
