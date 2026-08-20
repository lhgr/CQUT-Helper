import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SyncDiagnosticsPage extends StatefulWidget {
  const SyncDiagnosticsPage({super.key});

  @override
  State<SyncDiagnosticsPage> createState() => _SyncDiagnosticsPageState();
}

class _SyncDiagnosticsPageState extends State<SyncDiagnosticsPage> {
  bool _loading = true;
  bool _working = false;
  String _account = '';
  int _cachedWeeks = 0;
  ScheduleRefreshSnapshot? _refresh;
  CourseReminderStatus _reminders = const CourseReminderStatus.empty();
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
    final background = await loadScheduleUpdateWorkerHealthSnapshot();
    final notifications = await LocalNotifications.areNotificationsEnabled();
    final exactAlarm = await LocalNotifications.canScheduleExactNotifications();
    final batteryIgnored =
        await AndroidBackgroundRestrictions.isIgnoringBatteryOptimizations();
    final backgroundRestricted =
        await AndroidBackgroundRestrictions.isBackgroundRestricted();
    if (!mounted) return;
    setState(() {
      _account = account;
      _cachedWeeks = cachedWeeks;
      _refresh = refresh;
      _reminders = reminders;
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
        await controller.loadFromNetwork(updateWidgetPins: true);
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
      final granted =
          await LocalNotifications.ensureCourseReminderPermissions();
      if (!granted) throw StateError('通知或精确闹钟权限未授予');
      await CourseReminderScheduler.rescheduleForUser(_account);
    }, '课程提醒计划已重建');
  }

  String _time(DateTime? value) {
    if (value == null) return '暂无记录';
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.month}/${value.day} ${two(value.hour)}:${two(value.minute)}';
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
                        subtitle: _account.isEmpty ? '需要重新登录' : '本地账号信息正常',
                        good: _account.isNotEmpty,
                        onTap: _account.isEmpty
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
                Text('通知与后台', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      _statusTile(
                        icon: Icons.alarm_on_outlined,
                        title: _reminders.reason,
                        subtitle:
                            '已安排 ${_reminders.scheduledCount} 条 · '
                            '覆盖 ${_reminders.cachedWeekCount}/${_reminders.expectedWeekCount == 0 ? '?' : _reminders.expectedWeekCount} 周 · '
                            '下一条 ${_time(_reminders.nextReminderAt)}',
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
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _working
                      ? null
                      : () =>
                            AndroidBackgroundRestrictions.openAutoStartSettings(),
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('打开自启动设置'),
                ),
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
            ),
    );
  }
}
