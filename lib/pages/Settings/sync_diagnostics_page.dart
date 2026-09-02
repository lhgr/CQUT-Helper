import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncDiagnosticsPage extends StatefulWidget {
  final Future<String?> Function()? readEncryptedPassword;

  const SyncDiagnosticsPage({super.key, this.readEncryptedPassword});

  @override
  State<SyncDiagnosticsPage> createState() => _SyncDiagnosticsPageState();
}

class _SyncDiagnosticsPageState extends State<SyncDiagnosticsPage> {
  bool _loading = true;
  bool _working = false;
  String _account = '';
  bool _hasCredential = false;
  bool _credentialReadFailed = false;
  int _cachedWeeks = 0;
  ScheduleRefreshSnapshot? _refresh;
  CourseReminderStatus _reminders = const CourseReminderStatus.empty();
  bool _noticeEnhancementEnabled = false;
  ScheduleBackgroundPollHealthSnapshot? _background;
  bool _notifications = false;
  bool _exactAlarm = false;
  bool? _batteryIgnored;
  bool? _backgroundRestricted;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final prefs = await SharedPreferences.getInstance();
    final account = (prefs.getString('account') ?? '').trim();
    var hasCredential = false;
    var credentialReadFailed = false;
    if (account.isNotEmpty) {
      try {
        final encryptedPassword =
            await (widget.readEncryptedPassword?.call() ??
                CredentialStore().readEncryptedPassword());
        hasCredential = (encryptedPassword ?? '').trim().isNotEmpty;
      } catch (_) {
        credentialReadFailed = true;
      }
    }
    var cachedWeeks = 0;
    if (account.isNotEmpty) {
      try {
        cachedWeeks = await ScheduleCacheDatabase.instance.countForUser(
          account,
        );
      } catch (_) {}
    }
    final refresh = account.isEmpty
        ? null
        : await ScheduleRefreshState.load(account);
    final reminders = await CourseReminderScheduler.loadStatus();
    final noticeEnhancementEnabled =
        ScheduleSettingsManager.isNoticeEnhancementEnabledIn(prefs);
    final background = noticeEnhancementEnabled
        ? await loadScheduleUpdateWorkerHealthSnapshot()
        : null;
    final notifications = await LocalNotifications.areNotificationsEnabled();
    final exactAlarm = await LocalNotifications.canScheduleExactNotifications();
    final batteryIgnored = noticeEnhancementEnabled
        ? await AndroidBackgroundRestrictions.isIgnoringBatteryOptimizations()
        : null;
    final backgroundRestricted = noticeEnhancementEnabled
        ? await AndroidBackgroundRestrictions.isBackgroundRestricted()
        : null;
    if (!mounted) return;
    setState(() {
      _account = account;
      _hasCredential = hasCredential;
      _credentialReadFailed = credentialReadFailed;
      _cachedWeeks = cachedWeeks;
      _refresh = refresh;
      _reminders = reminders;
      _noticeEnhancementEnabled = noticeEnhancementEnabled;
      _background = background;
      _notifications = notifications;
      _exactAlarm = exactAlarm;
      _batteryIgnored = batteryIgnored;
      _backgroundRestricted = backgroundRestricted;
      _loading = false;
    });
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(success)));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('操作失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
      await _load();
    }
  }

  Future<void> _refreshSchedule() async {
    await _run(() async {
      final controller = ScheduleController();
      try {
        final currentData = await controller.loadFromNetwork(
          updateWidgetPins: true,
        );
        await controller.prefetchAllWeeksInBackground(
          currentData,
          () {},
          interval: Duration.zero,
        );
      } finally {
        controller.dispose();
      }
      await WidgetUpdater.updateTodayWidget(trigger: 'diagnostics_refresh');
      if (_account.isNotEmpty) {
        await CourseReminderScheduler.rescheduleForUser(_account);
      }
    }, '课表、组件和提醒已刷新');
  }

  Future<void> _repairReminders() async {
    await _run(() async {
      if (_account.isEmpty) throw StateError('未找到当前账号');
      final granted =
          await LocalNotifications.ensureCourseReminderPermissions();
      if (!granted) throw StateError('通知或精确闹钟权限未授予');
      final controller = ScheduleController();
      try {
        final currentData = await controller.loadFromNetwork(
          updateWidgetPins: true,
        );
        await controller.prefetchAllWeeksInBackground(
          currentData,
          () {},
          interval: Duration.zero,
        );
      } finally {
        controller.dispose();
      }
      await CourseReminderScheduler.rescheduleForUser(_account);
      final status = await CourseReminderScheduler.loadStatus();
      if (status.enabled && !status.ready) {
        throw StateError(status.reason);
      }
    }, '课程提醒计划已重建');
  }

  bool get _credentialInvalid =>
      _refresh?.failure == ScheduleWidgetRefreshFailure.credentialInvalid;

  bool get _needsReauthentication =>
      _account.isNotEmpty &&
      (_credentialReadFailed || !_hasCredential || _credentialInvalid);

  String get _accountSubtitle {
    if (_account.isEmpty) return '未检测到本地账号';
    if (_credentialReadFailed) return '无法读取安全存储中的登录凭据';
    if (!_hasCredential) return '账号存在，但登录凭据缺失';
    if (_credentialInvalid) return '最近一次同步判断登录凭据已失效';
    return '账号与登录凭据已保存；有效性会在同步时验证';
  }

  String _time(DateTime? value) {
    if (value == null) return '暂无记录';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.month}/${value.day} ${two(value.hour)}:${two(value.minute)}';
  }

  String get _reminderSubtitle {
    if (!_reminders.enabled) {
      return '开启课前提醒后，会根据已同步课表生成未来 60 天提醒';
    }
    final coverage = _reminders.expectedWeekCount > 0
        ? '覆盖 ${_reminders.cachedWeekCount}/${_reminders.expectedWeekCount} 周'
        : '覆盖范围待同步';
    return '已安排 ${_reminders.scheduledCount} 条 · '
        '$coverage · '
        '下一条 ${_time(_reminders.nextReminderAt)}';
  }

  Widget _statusTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool good,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: good ? scheme.primary : scheme.error),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('同步与诊断'),
        actions: [
          IconButton(
            onPressed: _loading || _working ? null : _load,
            tooltip: '重新检测',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Text('数据同步', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      _statusTile(
                        icon: Icons.person_outline,
                        title: _account.isEmpty ? '未登录' : '账号 $_account',
                        subtitle: _accountSubtitle,
                        good:
                            _account.isNotEmpty &&
                            !_credentialReadFailed &&
                            _hasCredential &&
                            !_credentialInvalid,
                        onTap: _account.isEmpty || _needsReauthentication
                            ? () async {
                                await requestReauthentication(context);
                                await _load();
                              }
                            : null,
                      ),
                      const Divider(height: 1),
                      _statusTile(
                        icon: Icons.cloud_done_outlined,
                        title: '已缓存 $_cachedWeeks 周课表',
                        subtitle:
                            '最后成功同步：${_time(_refresh?.lastSuccessfulRefreshAt)}',
                        good:
                            _cachedWeeks > 0 &&
                            _refresh?.lastSuccessfulRefreshAt != null,
                      ),
                      const Divider(height: 1),
                      _statusTile(
                        icon: Icons.widgets_outlined,
                        title: '桌面组件',
                        subtitle:
                            _refresh?.widgetState ==
                                ScheduleWidgetRefreshState.failed
                            ? '最近一次刷新失败'
                            : '刷新状态正常',
                        good:
                            _refresh?.widgetState !=
                            ScheduleWidgetRefreshState.failed,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _noticeEnhancementEnabled ? '通知与后台' : '通知',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      _statusTile(
                        icon: Icons.alarm_on_outlined,
                        title: _reminders.reason,
                        subtitle: _reminderSubtitle,
                        good: !_reminders.enabled || _reminders.ready,
                        onTap: _reminders.enabled ? _repairReminders : null,
                      ),
                      const Divider(height: 1),
                      _statusTile(
                        icon: Icons.notifications_active_outlined,
                        title: _notifications ? '通知权限正常' : '通知权限未授予',
                        subtitle: _exactAlarm ? '精确闹钟权限正常' : '精确闹钟权限未授予',
                        good: _notifications && _exactAlarm,
                        onTap: _notifications && _exactAlarm
                            ? null
                            : _repairReminders,
                      ),
                      if (_noticeEnhancementEnabled) ...[
                        const Divider(height: 1),
                        _statusTile(
                          icon: Icons.sync_outlined,
                          title: _background?.title ?? '后台状态未知',
                          subtitle: _background?.detail ?? '暂时无法读取后台任务状态',
                          good:
                              _background?.status ==
                              ScheduleBackgroundPollHealthStatus.healthy,
                          onTap: () => _run(
                            ScheduleUpdateWorker.syncFromPreferences,
                            '后台任务已重新注册',
                          ),
                        ),
                        const Divider(height: 1),
                        _statusTile(
                          icon: Icons.battery_saver_outlined,
                          title: _backgroundRestricted == true
                              ? '系统限制后台运行'
                              : '后台运行限制',
                          subtitle: _batteryIgnored == true
                              ? '已忽略电池优化'
                              : '建议允许忽略电池优化和自启动',
                          good:
                              _backgroundRestricted != true &&
                              _batteryIgnored == true,
                          onTap: AndroidBackgroundRestrictions
                              .openBatteryOptimizationSettings,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _working || _account.isEmpty
                      ? null
                      : _refreshSchedule,
                  icon: _working
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(_working ? '正在处理…' : '立即刷新课表、组件和提醒'),
                ),
                if (_noticeEnhancementEnabled) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _working
                        ? null
                        : () =>
                              AndroidBackgroundRestrictions.openAutoStartSettings(),
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('打开自启动设置'),
                  ),
                ],
                if (_needsReauthentication) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: _working
                        ? null
                        : () async {
                            if (await requestReauthentication(context) &&
                                mounted) {
                              await _refreshSchedule();
                            }
                          },
                    icon: const Icon(Icons.login),
                    label: const Text('重新验证登录'),
                  ),
                ],
              ],
            ),
    );
  }
}
