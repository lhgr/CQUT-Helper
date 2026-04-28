import 'dart:convert';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/schedule_notice_refresh_pipeline.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

@pragma('vm:entry-point')
void scheduleUpdateCallbackDispatcher() {
  ScheduleUpdateWorker.callbackDispatcher();
}

class ScheduleUpdateWorker {
  static const String _taskName = 'schedule_notice_poll_task';
  static const String _immediateTaskUniqueName =
      'schedule_notice_poll_task_immediate';
  static const int _frequencyMinutes = 60;
  static const String _lastViewedWeekKeyPrefix = 'schedule_last_week_';
  static const String _lastViewedTermKeyPrefix = 'schedule_last_term_';
  static const String _widgetWeekKeyPrefix = 'schedule_widget_week_';
  static const String _widgetTermKeyPrefix = 'schedule_widget_term_';
  static bool _loggerReady = false;

  static String pendingKeyForUser(String userId) =>
      'schedule_pending_changes_$userId';

  static String _lastViewedWeekKey(String userId) =>
      '$_lastViewedWeekKeyPrefix$userId';

  static String _lastViewedTermKey(String userId) =>
      '$_lastViewedTermKeyPrefix$userId';

  static String _widgetWeekKey(String userId) => '$_widgetWeekKeyPrefix$userId';

  static String _widgetTermKey(String userId) => '$_widgetTermKeyPrefix$userId';

  static bool _isValidTerm(String value) =>
      RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(value.trim());

  static String _normalizeWeek(String value) {
    final raw = value.trim();
    if (raw.isEmpty) return '1';
    if (!RegExp(r'^\d+$').hasMatch(raw)) return '1';
    return raw;
  }

  @visibleForTesting
  static ({String? yearTerm, String weekNum}) resolvePollingTarget({
    required SharedPreferences prefs,
    required String userId,
  }) {
    final lastTerm = (prefs.getString(_lastViewedTermKey(userId)) ?? '').trim();
    final widgetTerm = (prefs.getString(_widgetTermKey(userId)) ?? '').trim();
    // 后台轮询以“当前学期”（学期选择中的标记）为准，优先读取 widget 锚点。
    final selectedTerm = _isValidTerm(widgetTerm)
        ? widgetTerm
        : (_isValidTerm(lastTerm) ? lastTerm : null);
    final lastWeek = (prefs.getString(_lastViewedWeekKey(userId)) ?? '').trim();
    final widgetWeek = (prefs.getString(_widgetWeekKey(userId)) ?? '').trim();
    final selectedWeek = _normalizeWeek(
      widgetWeek.isNotEmpty ? widgetWeek : lastWeek,
    );
    return (yearTerm: selectedTerm, weekNum: selectedWeek);
  }

  static Future<void> initialize() async {
    await Workmanager().initialize(
      scheduleUpdateCallbackDispatcher,
      isInDebugMode: false,
    );
  }

  static Future<void> syncFromPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    final encryptedPassword = (prefs.getString('encrypted_password') ?? '')
        .trim();
    final enabled =
        prefs.getBool('schedule_background_polling_enabled') ?? false;
    await _recordSyncState(
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
      await _recordSyncState(
        status: 'sync_cancelled',
        fields: {
          'enabled': enabled,
          'hasUserId': userId.isNotEmpty,
          'hasPassword': encryptedPassword.isNotEmpty,
        },
      );
      return;
    }
    try {
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
      await _recordSyncState(
        status: 'sync_registered',
        fields: {'frequencyMinutes': _frequencyMinutes},
      );
    } catch (e) {
      await _recordSyncState(
        status: 'sync_register_failed',
        fields: {'error': e.toString()},
      );
      rethrow;
    }
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      WidgetsFlutterBinding.ensureInitialized();
      await _ensureLoggerReady();
      final runId = AppLogger.I.newTraceId();
      return AppLogger.I.runWithTraceIdAsync(runId, () async {
        final trigger = ((inputData?['trigger'] ?? 'unknown').toString()).trim();
        await _recordWorkerState(
          status: 'started',
          trigger: trigger,
          task: task,
          runId: runId,
          fields: {'run_id': runId},
        );
        Future<bool> done({
          required String status,
          Map<String, Object?> fields = const {},
        }) async {
          final mergedFields = <String, Object?>{'run_id': runId, ...fields};
          await _recordWorkerState(
            status: status,
            trigger: trigger,
            task: task,
            runId: runId,
            fields: mergedFields,
          );
          await AppLogger.I.flush();
          return true;
        }

        if (task != _taskName) {
          AppLogger.I.event(
            LogLevel.info,
            'ScheduleUpdateWorker',
            event: 'schedule_worker_task_skip',
            messageZh: '后台轮询跳过未知任务',
            message: 'skip unknown task',
            module: 'schedule',
            action: 'poll',
            status: 'skip',
            reason: 'unknown_task',
            fields: {'task': task, 'trigger': trigger, 'run_id': runId},
          );
          return done(status: 'skip_unknown_task');
        }
        AppLogger.I.event(
          LogLevel.info,
          'ScheduleUpdateWorker',
          event: 'schedule_worker_task_start',
          messageZh: '后台轮询任务开始执行',
          message: 'heartbeat task started',
          module: 'schedule',
          action: 'poll',
          status: 'start',
          fields: {'task': task, 'trigger': trigger, 'run_id': runId},
        );
        if (_isDeepNight()) {
          AppLogger.I.event(
            LogLevel.info,
            'ScheduleUpdateWorker',
            event: 'schedule_worker_task_skip',
            messageZh: '后台轮询跳过深夜时段',
            message: 'skip deep night window',
            module: 'schedule',
            action: 'poll',
            status: 'skip',
            reason: 'deep_night',
            fields: {'trigger': trigger, 'run_id': runId},
          );
          return done(status: 'skip_deep_night');
        }
        final userId = ((inputData?['userId'] ?? '').toString()).trim();
        final encryptedPassword =
            ((inputData?['encryptedPassword'] ?? '').toString()).trim();
        if (userId.isEmpty || encryptedPassword.isEmpty) {
          AppLogger.I.event(
            LogLevel.warn,
            'ScheduleUpdateWorker',
            event: 'schedule_worker_task_skip',
            messageZh: '后台轮询跳过：缺少任务凭证',
            message: 'skip missing task credentials',
            module: 'schedule',
            action: 'poll',
            status: 'skip',
            reason: 'missing_credentials',
            fields: {'trigger': trigger, 'run_id': runId},
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
            event: 'schedule_worker_load_cache_fail',
            messageZh: '后台轮询读取缓存失败',
            message: 'load cache failed',
            module: 'schedule',
            action: 'load_cache',
            status: 'fail',
            reason: 'cache_load_error',
            error: e,
            stackTrace: st,
            fields: {'trigger': trigger, 'run_id': runId},
          );
        }
        if (currentData == null) {
          AppLogger.I.event(
            LogLevel.info,
            'ScheduleUpdateWorker',
            event: 'schedule_worker_load_network_start',
            messageZh: '缓存未命中，开始走网络拉取课表',
            message: 'cache miss fallback to network',
            module: 'schedule',
            action: 'load_network',
            status: 'start',
            fields: {
              'trigger': trigger,
              'preferredTerm': preferredTerm,
              'preferredWeek': preferredWeek,
              'run_id': runId,
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
              LogLevel.warn,
              'ScheduleUpdateWorker',
              event: 'schedule_worker_load_network_fail',
              messageZh: '后台轮询网络拉取课表失败',
              message: 'load network failed',
              module: 'schedule',
              action: 'load_network',
              status: 'fail',
              reason: 'network_load_error',
              error: e,
              stackTrace: st,
              fields: {'trigger': trigger, 'run_id': runId},
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
            event: 'schedule_worker_task_skip',
            messageZh: '后台轮询跳过：课表数据无效',
            message: 'skip invalid schedule data',
            module: 'schedule',
            action: 'poll',
            status: 'skip',
            reason: 'invalid_schedule_data',
            fields: {'trigger': trigger, 'run_id': runId},
          );
          return done(status: 'skip_invalid_schedule_data');
        }
        if (preferredTerm.isNotEmpty &&
            currentData.yearTerm!.trim() != preferredTerm) {
          AppLogger.I.event(
            LogLevel.warn,
            'ScheduleUpdateWorker',
            event: 'schedule_worker_task_skip',
            messageZh: '后台轮询跳过：轮询学期与当前学期不一致',
            message: 'polling term mismatch',
            module: 'schedule',
            action: 'poll',
            status: 'skip',
            reason: 'term_mismatch',
            fields: {
              'trigger': trigger,
              'preferredTerm': preferredTerm,
              'currentTerm': currentData.yearTerm!.trim(),
              'run_id': runId,
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
            LogLevel.warn,
            'ScheduleUpdateWorker',
            event: 'schedule_worker_pipeline_fail',
            messageZh: '后台轮询执行变更流水线失败',
            message: 'pipeline run failed',
            module: 'schedule',
            action: 'pipeline',
            status: 'fail',
            reason: 'pipeline_error',
            error: e,
            stackTrace: st,
            fields: {'trigger': trigger, 'run_id': runId},
          );
          return done(status: 'pipeline_failed', fields: {'error': e.toString()});
        }

        if (result.apiClosed || result.changes.isEmpty) {
          AppLogger.I.event(
            LogLevel.info,
            'ScheduleUpdateWorker',
            event: 'schedule_worker_task_finish',
            messageZh: '后台轮询完成，无课表变更',
            message: 'heartbeat task finished without changes',
            module: 'schedule',
            action: 'poll',
            status: 'ok',
            reason: result.apiClosed ? 'api_closed' : 'no_changes',
            fields: {
              'trigger': trigger,
              'apiClosed': result.apiClosed,
              'changes': result.changes.length,
              'run_id': runId,
            },
          );
          return done(
            status: result.apiClosed ? 'api_closed' : 'no_changes',
            fields: {
              'apiClosed': result.apiClosed,
              'changes': result.changes.length,
            },
          );
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
        AppLogger.I.event(
          LogLevel.info,
          'ScheduleUpdateWorker',
          event: 'schedule_worker_task_finish',
          messageZh: '后台轮询完成，检测到课表变更',
          message: 'heartbeat task detected schedule changes',
          module: 'schedule',
          action: 'poll',
          status: 'ok',
          fields: {
            'trigger': trigger,
            'changes': result.changes.length,
            'run_id': runId,
          },
        );
        return done(
          status: 'changes_detected',
          fields: {'changes': result.changes.length},
        );
      });
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

  static Future<void> _recordWorkerState({
    required String status,
    required String trigger,
    required String task,
    String? runId,
    Map<String, Object?> fields = const {},
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'schedule_background_poll_last_state',
        json.encode({
          'at': DateTime.now().toIso8601String(),
          'status': status,
          'trigger': trigger,
          'task': task,
          'runId': runId,
          'fields': fields,
        }),
      );
    } catch (_) {}
  }

  static Future<void> _recordSyncState({
    required String status,
    Map<String, Object?> fields = const {},
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'schedule_background_poll_sync_state',
        json.encode({
          'at': DateTime.now().toIso8601String(),
          'status': status,
          'fields': fields,
        }),
      );
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
