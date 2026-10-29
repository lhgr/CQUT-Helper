import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum DiagnosticCondition { normal, off, pending, problem }

enum DiagnosticRead {
  settings,
  credential,
  cache,
  refresh,
  reminders,
  notifications,
  exactAlarm,
  background,
  battery,
  restriction,
}

class SyncDiagnosticsSnapshot {
  final String? account;
  final bool? hasCredential;
  final bool? remindersEnabled;
  final bool enhancementEnabled;
  final int? cachedWeeks;
  final ScheduleRefreshSnapshot? refresh;
  final CourseReminderStatus? reminders;
  final bool? notifications;
  final bool? exactAlarm;
  final ScheduleBackgroundPollHealthSnapshot? background;
  final bool? batteryIgnored;
  final bool? backgroundRestricted;
  final Set<DiagnosticRead> failures;

  const SyncDiagnosticsSnapshot({
    this.account,
    this.hasCredential,
    this.remindersEnabled,
    this.enhancementEnabled = false,
    this.cachedWeeks,
    this.refresh,
    this.reminders,
    this.notifications,
    this.exactAlarm,
    this.background,
    this.batteryIgnored,
    this.backgroundRestricted,
    this.failures = const {},
  });

  bool get credentialInvalid =>
      refresh?.failure == ScheduleWidgetRefreshFailure.credentialInvalid;
  bool get needsLogin =>
      account != null &&
      (account!.isEmpty || hasCredential == false || credentialInvalid);
  DiagnosticCondition get accountCondition => needsLogin
      ? DiagnosticCondition.problem
      : hasCredential == null
      ? DiagnosticCondition.pending
      : DiagnosticCondition.normal;
  DiagnosticCondition get reminderCondition {
    if (remindersEnabled == false) return DiagnosticCondition.off;
    if (remindersEnabled == null ||
        reminders == null ||
        notifications == null ||
        exactAlarm == null) {
      return DiagnosticCondition.pending;
    }
    if (notifications == false || exactAlarm == false) {
      return DiagnosticCondition.problem;
    }
    if (reminders!.updatedAt == null || !reminders!.enabled) {
      return DiagnosticCondition.pending;
    }
    return reminders!.ready
        ? DiagnosticCondition.normal
        : DiagnosticCondition.problem;
  }

  DiagnosticCondition get backgroundCondition {
    if (notifications == false ||
        backgroundRestricted == true ||
        batteryIgnored == false) {
      return DiagnosticCondition.problem;
    }
    if (background == null) return DiagnosticCondition.pending;
    if (background!.status == ScheduleBackgroundPollHealthStatus.failed ||
        background!.status == ScheduleBackgroundPollHealthStatus.restricted) {
      return DiagnosticCondition.problem;
    }
    if (notifications == null ||
        batteryIgnored == null ||
        backgroundRestricted == null) {
      return DiagnosticCondition.pending;
    }
    return switch (background!.status) {
      ScheduleBackgroundPollHealthStatus.failed ||
      ScheduleBackgroundPollHealthStatus.restricted =>
        DiagnosticCondition.problem,
      ScheduleBackgroundPollHealthStatus.observing =>
        DiagnosticCondition.pending,
      _ => DiagnosticCondition.normal,
    };
  }
}

class SyncActionResult {
  final List<String> details;
  final bool hasFailure;
  final bool needsLogin;
  final bool permissionDenied;
  final WidgetUpdateResult? widgetResult;
  final int completedStages;

  const SyncActionResult({
    required this.details,
    this.hasFailure = false,
    this.needsLogin = false,
    this.permissionDenied = false,
    this.widgetResult,
    this.completedStages = 0,
  });
  String get title => hasFailure
      ? completedStages > 0
            ? '部分操作未完成，请查看结果'
            : '操作未完成，请查看结果'
      : completedStages > 0
      ? '操作已完成'
      : '操作结果';
}

/// The page's existing services, kept together so reads and actions can be
/// exercised without invoking platform plugins in widget tests.
class SyncDiagnosticsService {
  final Future<String?> Function()? readEncryptedPassword;
  SyncDiagnosticsService({this.readEncryptedPassword});

  Future<SharedPreferences> readPreferences() =>
      SharedPreferences.getInstance();
  Future<String?> readCredential() =>
      readEncryptedPassword?.call() ??
      CredentialStore().readEncryptedPassword();
  Future<int> readCachedWeeks(String account) =>
      ScheduleCacheDatabase.instance.countForUser(account);
  Future<ScheduleRefreshSnapshot> readRefresh(String account) =>
      ScheduleRefreshState.load(account);
  Future<CourseReminderStatus> readReminders() =>
      CourseReminderScheduler.loadStatus();
  Future<bool> readNotifications() =>
      LocalNotifications.areNotificationsEnabled();
  Future<bool> readExactAlarm() =>
      LocalNotifications.canScheduleExactNotifications();
  Future<ScheduleBackgroundPollHealthSnapshot> readBackground() =>
      loadScheduleUpdateWorkerHealthSnapshot();
  Future<bool?> readBatteryIgnored() =>
      AndroidBackgroundRestrictions.isIgnoringBatteryOptimizations();
  Future<bool?> readBackgroundRestricted() =>
      AndroidBackgroundRestrictions.isBackgroundRestricted();
  ScheduleController createController() => ScheduleController();
  Future<WidgetUpdateResult> refreshWidget() =>
      WidgetUpdater.updateTodayWidget(trigger: 'diagnostics_refresh');
  Future<void> rescheduleReminders(String account) =>
      CourseReminderScheduler.rescheduleForUser(account);
  Future<bool> requestReminderPermissions() =>
      LocalNotifications.ensureCourseReminderPermissions();
  Future<void> resetBackground() => ScheduleUpdateWorker.syncFromPreferences();
  Future<bool> openBatterySettings() =>
      AndroidBackgroundRestrictions.openBatteryOptimizationSettings();
  Future<bool> openAutoStartSettings() =>
      AndroidBackgroundRestrictions.openAutoStartSettings();
  Future<bool> openAppSettings() =>
      AndroidBackgroundRestrictions.openAppDetailsSettings();

  void logFailure(String operation, Object error, StackTrace stack) {
    AppLogger.I.logOperationFailure(
      'SyncDiagnostics',
      operation,
      error: error,
      stackTrace: stack,
    );
  }

  Future<SyncDiagnosticsSnapshot> load() async {
    final failures = <DiagnosticRead>{};
    Future<T?> read<T>(
      DiagnosticRead item,
      Future<T?> Function() action,
    ) async {
      try {
        return await action();
      } catch (error, stack) {
        failures.add(item);
        logFailure('read ${item.name} failed', error, stack);
        return null;
      }
    }

    final prefs = await read(DiagnosticRead.settings, readPreferences);
    final account = prefs == null
        ? null
        : await read<String>(
            DiagnosticRead.settings,
            () async => (prefs.getString('account') ?? '').trim(),
          );
    final remindersEnabled = prefs == null
        ? null
        : await read<bool>(
            DiagnosticRead.settings,
            () async =>
                prefs.getBool(ScheduleSettingsManager.remindersEnabledKey) ??
                false,
          );
    final enhancementEnabled =
        prefs != null &&
        await read<bool>(
              DiagnosticRead.settings,
              () async =>
                  ScheduleSettingsManager.isNoticeEnhancementEnabledIn(prefs),
            ) ==
            true;
    bool? credential;
    int? cachedWeeks;
    ScheduleRefreshSnapshot? refresh;
    CourseReminderStatus? reminders;
    bool? notifications;
    bool? exactAlarm;
    ScheduleBackgroundPollHealthSnapshot? background;
    bool? battery;
    bool? restriction;
    await Future.wait<void>([
      if (account != null && account.isNotEmpty) ...[
        (() async {
          final value = await read(DiagnosticRead.credential, readCredential);
          credential = value == null
              ? (failures.contains(DiagnosticRead.credential) ? null : false)
              : value.trim().isNotEmpty;
        })(),
        (() async {
          cachedWeeks = await read(
            DiagnosticRead.cache,
            () => readCachedWeeks(account),
          );
        })(),
        (() async {
          refresh = await read(
            DiagnosticRead.refresh,
            () => readRefresh(account),
          );
        })(),
      ],
      (() async {
        reminders = await read(DiagnosticRead.reminders, readReminders);
      })(),
      if (remindersEnabled == true || enhancementEnabled)
        (() async {
          notifications = await read(
            DiagnosticRead.notifications,
            readNotifications,
          );
        })(),
      if (remindersEnabled == true)
        (() async {
          exactAlarm = await read(DiagnosticRead.exactAlarm, readExactAlarm);
        })(),
      if (enhancementEnabled) ...[
        (() async {
          background = await read(DiagnosticRead.background, readBackground);
        })(),
        (() async {
          battery = await read(DiagnosticRead.battery, readBatteryIgnored);
        })(),
        (() async {
          restriction = await read(
            DiagnosticRead.restriction,
            readBackgroundRestricted,
          );
        })(),
      ],
    ]);
    return SyncDiagnosticsSnapshot(
      account: account,
      hasCredential: credential,
      remindersEnabled: remindersEnabled,
      enhancementEnabled: enhancementEnabled,
      cachedWeeks: cachedWeeks,
      refresh: refresh,
      reminders: reminders,
      notifications: notifications,
      exactAlarm: exactAlarm,
      background: background,
      batteryIgnored: battery,
      backgroundRestricted: restriction,
      failures: Set.unmodifiable(failures),
    );
  }

  Future<SyncActionResult> synchronize(
    SyncDiagnosticsSnapshot snapshot, {
    bool repairReminders = false,
  }) async {
    final details = <String>[];
    var failed = false;
    var needsLogin = false;
    var permissionDenied = false;
    var completedStages = 0;
    WidgetUpdateResult? widgetResult;
    Future<bool> stage(String name, Future<void> Function() action) async {
      try {
        await action();
        return true;
      } catch (error, stack) {
        failed = true;
        needsLogin |= ScheduleRefreshState.looksLikeCredentialFailure(error);
        details.add('$name未完成，请重试${needsLogin ? '或重新登录' : ''}');
        logFailure('$name failed', error, stack);
        return false;
      }
    }

    // Read the switch again so a disabled reminder is never rebuilt from a
    // stale diagnostic snapshot or stale scheduler status.
    bool? remindersEnabled;
    await stage('读取提醒设置', () async {
      final prefs = await readPreferences();
      remindersEnabled =
          prefs.getBool(ScheduleSettingsManager.remindersEnabledKey) ?? false;
    });
    if (repairReminders) {
      if (remindersEnabled != true) {
        details.add(
          remindersEnabled == false ? '课前提醒未开启，请先在通知设置中开启' : '提醒设置暂时无法获取，请重试',
        );
        return SyncActionResult(details: details, hasFailure: failed);
      }
      var granted = false;
      final checked = await stage('获取提醒权限', () async {
        granted = await requestReminderPermissions();
      });
      if (!checked) {
        details.add('提醒权限暂时无法获取，请稍后重试');
        return SyncActionResult(details: details, hasFailure: true);
      }
      if (!granted) {
        details.add('提醒权限未授予，请在系统设置中允许通知与精确闹钟后重试');
        return SyncActionResult(
          details: details,
          hasFailure: true,
          permissionDenied: true,
        );
      }
    }
    final account = snapshot.account;
    if (account == null ||
        account.isEmpty ||
        snapshot.hasCredential == false ||
        snapshot.credentialInvalid) {
      failed = true;
      needsLogin = true;
      details.add('课表同步未完成，请重新登录');
    } else {
      ScheduleController? controller;
      var currentLoaded = false;
      await stage('课表同步', () async {
        controller = createController();
        final data = await controller!.loadFromNetwork(updateWidgetPins: true);
        currentLoaded = true;
        completedStages++;
        details.add('当前周课表已更新');
        await stage('全学期课表同步', () async {
          final result = await controller!.prefetchAllWeeksInBackground(
            data,
            () {},
            interval: Duration.zero,
            forceRefresh: true,
          );
          if (!result.completed || result.failedWeeks.isNotEmpty) {
            failed = true;
            details.add(
              result.failedWeeks.isEmpty
                  ? '全学期同步尚未完成，请重试'
                  : '全学期同步有 ${result.failedWeeks.length} 周未完成，请重试',
            );
          } else {
            completedStages++;
            details.add('全学期课表已更新');
          }
        });
      });
      if (!currentLoaded) details.add('全学期同步未开始，需先完成当前课表同步');
      controller?.dispose();
    }
    if (!repairReminders) {
      await stage('组件刷新请求', () async {
        widgetResult = await refreshWidget();
        switch (widgetResult!) {
          case WidgetUpdateResult.accepted:
            completedStages++;
            details.add('已请求刷新桌面组件，显示结果请查看桌面');
          case WidgetUpdateResult.failed:
            failed = true;
            details.add('组件刷新请求失败，可再次立即同步');
          case WidgetUpdateResult.notSupported:
            details.add('当前平台不支持桌面组件');
        }
      });
    }
    if (remindersEnabled == true) {
      await stage('提醒更新', () async {
        if (!await readNotifications() || !await readExactAlarm()) {
          failed = true;
          permissionDenied = true;
          details.add('提醒权限未授予，请在系统设置中允许通知与精确闹钟后修复提醒');
          return;
        }
        if (account == null || account.isEmpty) {
          failed = true;
          details.add('提醒更新需要先登录');
          return;
        }
        await rescheduleReminders(account);
        final status = await readReminders();
        if (status.ready) {
          completedStages++;
          details.add(
            status.scheduledCount == 0 ? '提醒已就绪，未来 60 天没有需要提醒的课程' : '课前提醒已更新',
          );
        } else {
          failed = true;
          details.add('提醒尚未就绪：${status.reason}');
        }
      });
    } else if (!repairReminders) {
      details.add(
        remindersEnabled == false ? '课前提醒未开启，本次无需更新' : '提醒设置暂时无法获取，请重试',
      );
    }
    return SyncActionResult(
      details: details,
      hasFailure: failed,
      needsLogin: needsLogin,
      permissionDenied: permissionDenied,
      widgetResult: widgetResult,
      completedStages: completedStages,
    );
  }
}
