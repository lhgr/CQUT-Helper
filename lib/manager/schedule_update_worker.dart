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

enum ScheduleBackgroundPollHealthStatus {
  observing,
  healthy,
  failed,
  pausedAtNight,
  restricted,
}

class ScheduleBackgroundPollHealthSnapshot {
  final ScheduleBackgroundPollHealthStatus status;
  final String title;
  final String detail;
  final DateTime? enabledAt;
  final DateTime? lastRunAt;
  final DateTime? lastSuccessAt;
  final String? lastRunStatus;

  const ScheduleBackgroundPollHealthSnapshot({
    required this.status,
    required this.title,
    required this.detail,
    this.enabledAt,
    this.lastRunAt,
    this.lastSuccessAt,
    this.lastRunStatus,
  });
}

class ScheduleUpdateWorker {
  static const String _taskName = 'schedule_notice_poll_task';
  static const String _immediateTaskUniqueName =
      'schedule_notice_poll_task_immediate';
  static const int _frequencyMinutes = 60;
  static const String _lastViewedWeekKeyPrefix = 'schedule_last_week_';
  static const String _backgroundPollingEnabledAtKey =
      'schedule_background_poll_enabled_at';
  static const String _backgroundPollingLastSuccessAtKey =
      'schedule_background_poll_last_success_at';
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

  static Future<void> markEnabledAtIfNeeded({required bool enabled}) async {
    final prefs = await SharedPreferences.getInstance();
    if (!enabled) {
      await prefs.remove(_backgroundPollingEnabledAtKey);
      await prefs.remove(_backgroundPollingLastSuccessAtKey);
      await prefs.remove('schedule_background_poll_last_state');
      await prefs.remove('schedule_background_poll_sync_state');
      return;
    }
    if (prefs.getString(_backgroundPollingEnabledAtKey)?.trim().isNotEmpty ==
        true) {
      return;
    }
    await prefs.setString(
      _backgroundPollingEnabledAtKey,
      DateTime.now().toIso8601String(),
    );
  }

  static Future<ScheduleBackgroundPollHealthSnapshot>
  loadHealthSnapshot() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled =
        prefs.getBool('schedule_background_polling_enabled') ?? false;
    if (!enabled) {
      return const ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.observing,
        title: '后台定时轮询已关闭',
        detail: '开启后会在后台定时检查调课通知。',
      );
    }

    DateTime? parseTime(String key) {
      final raw = (prefs.getString(key) ?? '').trim();
      if (raw.isEmpty) return null;
      return DateTime.tryParse(raw)?.toLocal();
    }

    Map<String, dynamic>? parseState(String key) {
      final raw = (prefs.getString(key) ?? '').trim();
      if (raw.isEmpty) return null;
      try {
        final decoded = json.decode(raw);
        return decoded is Map<String, dynamic> ? decoded : null;
      } catch (_) {
        return null;
      }
    }

    final enabledAt = parseTime(_backgroundPollingEnabledAtKey);
    final lastSuccessAt = parseTime(_backgroundPollingLastSuccessAtKey);
    final lastState = parseState('schedule_background_poll_last_state');
    final syncState = parseState('schedule_background_poll_sync_state');
    final lastRunAt = DateTime.tryParse(
      ((lastState?['at'] ?? '') as String?)?.trim() ?? '',
    )?.toLocal();
    final lastRunStatus = ((lastState?['status'] ?? '') as String?)?.trim();
    final syncStatus = ((syncState?['status'] ?? '') as String?)?.trim();
    final now = DateTime.now();
    final observeWindow = const Duration(hours: 2);
    final staleWindow = Duration(minutes: _frequencyMinutes * 3);

    if (enabledAt == null || now.difference(enabledAt) < observeWindow) {
      return ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.observing,
        title: '后台定时轮询观察中',
        detail: '刚开启后台定时轮询，系统需要一段时间建立后台执行记录。',
        enabledAt: enabledAt,
        lastRunAt: lastRunAt,
        lastSuccessAt: lastSuccessAt,
        lastRunStatus: lastRunStatus,
      );
    }

    if (lastSuccessAt != null && now.difference(lastSuccessAt) <= staleWindow) {
      return ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.healthy,
        title: '后台定时轮询运行正常',
        detail: '最近已检测到后台轮询成功执行。',
        enabledAt: enabledAt,
        lastRunAt: lastRunAt,
        lastSuccessAt: lastSuccessAt,
        lastRunStatus: lastRunStatus,
      );
    }

    if (lastRunStatus == 'skip_deep_night' &&
        lastRunAt != null &&
        now.difference(lastRunAt) <= staleWindow) {
      return ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.pausedAtNight,
        title: '后台定时轮询夜间暂停',
        detail: '应用会在 0:00-7:00 跳过后台轮询，白天会继续自动检查。',
        enabledAt: enabledAt,
        lastRunAt: lastRunAt,
        lastSuccessAt: lastSuccessAt,
        lastRunStatus: lastRunStatus,
      );
    }

    const failureStatuses = {
      'load_network_failed',
      'pipeline_failed',
      'skip_missing_credentials',
      'skip_invalid_schedule_data',
      'skip_term_mismatch',
    };
    if (lastRunStatus != null &&
        failureStatuses.contains(lastRunStatus) &&
        lastRunAt != null &&
        now.difference(lastRunAt) <= staleWindow) {
      return ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.failed,
        title: '后台定时轮询最近失败',
        detail: '后台任务最近执行过，但本次未成功完成，可稍后重试或检查登录状态与网络。',
        enabledAt: enabledAt,
        lastRunAt: lastRunAt,
        lastSuccessAt: lastSuccessAt,
        lastRunStatus: lastRunStatus,
      );
    }

    if (syncStatus != 'sync_registered') {
      return ScheduleBackgroundPollHealthSnapshot(
        status: ScheduleBackgroundPollHealthStatus.failed,
        title: '后台定时轮询尚未完成注册',
        detail: '后台任务尚未成功注册，请重新保存设置后再观察运行状态。',
        enabledAt: enabledAt,
        lastRunAt: lastRunAt,
        lastSuccessAt: lastSuccessAt,
        lastRunStatus: lastRunStatus,
      );
    }

    return ScheduleBackgroundPollHealthSnapshot(
      status: ScheduleBackgroundPollHealthStatus.restricted,
      title: '后台定时轮询可能受系统限制',
      detail: '长时间未检测到后台执行记录，建议检查通知权限、忽略电池优化与自启动设置。',
      enabledAt: enabledAt,
      lastRunAt: lastRunAt,
      lastSuccessAt: lastSuccessAt,
      lastRunStatus: lastRunStatus,
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
  }

  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    Workmanager().executeTask((task, inputData) async {
      WidgetsFlutterBinding.ensureInitialized();
      await _ensureLoggerReady();
      final trigger = ((inputData?['trigger'] ?? 'unknown').toString()).trim();
      await _recordWorkerState(status: 'started', trigger: trigger, task: task);
      Future<bool> done({
        required String status,
        Map<String, Object?> fields = const {},
      }) async {
        await _recordWorkerState(
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
        await _recordSuccessfulRun();
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
      await _recordSuccessfulRun();
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

  static Future<void> _recordSuccessfulRun() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _backgroundPollingLastSuccessAtKey,
        DateTime.now().toIso8601String(),
      );
    } catch (_) {}
  }

  static Future<void> _recordWorkerState({
    required String status,
    required String trigger,
    required String task,
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
