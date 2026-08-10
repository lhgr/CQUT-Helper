import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/widgets/app_select_field.dart';
import 'package:flutter/material.dart';

import 'settings_schedule_scope.dart';

class NotificationSettingsPage extends StatefulWidget {
  final SettingsScheduleScope scope;

  const NotificationSettingsPage({super.key, required this.scope});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  final ScheduleSettingsManager _manager = ScheduleSettingsManager();
  final TextEditingController _serviceController = TextEditingController();
  bool _loading = true;
  bool _working = false;
  bool _remindersEnabled = false;
  bool _exactAlarmGranted = false;
  int _reminderMinutes = 10;
  bool _pollingEnabled = false;
  ScheduleBackgroundPollHealthSnapshot? _health;
  String? _serviceError;
  String _connectivityMessage = '';
  bool _testingConnectivity = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _serviceController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _manager.load();
    final exactAlarmGranted = _manager.remindersEnabled
        ? await LocalNotifications.canScheduleExactNotifications()
        : false;
    final health = await ScheduleUpdateWorker.loadHealthSnapshot();
    if (!mounted) return;
    final serviceUrl = _manager.noticeApiBaseUrl;
    _serviceController.text =
        serviceUrl == ScheduleSettingsManager.officialNoticeApiBaseUrl
        ? ''
        : serviceUrl;
    setState(() {
      _remindersEnabled = _manager.remindersEnabled;
      _exactAlarmGranted = exactAlarmGranted;
      _reminderMinutes = _manager.defaultReminderMinutes;
      _pollingEnabled = _manager.backgroundPollingEnabled;
      _health = health;
      _loading = false;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveExperience() async {
    await _manager.saveExperienceSettings(
      remindersEnabled: _remindersEnabled,
      defaultReminderMinutes: _reminderMinutes,
      displayDensity: _manager.displayDensity,
      defaultHomeTab: _manager.defaultHomeTab,
    );
  }

  Future<void> _toggleReminders(bool value) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (value &&
          !await LocalNotifications.ensureCourseReminderPermissions()) {
        if (!mounted) return;
        setState(() => _exactAlarmGranted = false);
        _showMessage('需要通知和“闹钟与提醒”权限才能启用课前提醒');
        return;
      }
      if (!mounted) return;
      setState(() {
        _remindersEnabled = value;
        _exactAlarmGranted = value;
      });
      await _saveExperience();
      if (value && widget.scope.userId.isNotEmpty) {
        await CourseReminderScheduler.rescheduleForUser(widget.scope.userId);
      } else {
        await CourseReminderScheduler.cancelAll();
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changeReminderMinutes(int value) async {
    setState(() => _reminderMinutes = value);
    await _saveExperience();
    if (_remindersEnabled && widget.scope.userId.isNotEmpty) {
      await CourseReminderScheduler.rescheduleForUser(widget.scope.userId);
    }
  }

  Future<bool> _confirmPollingConsent() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('开启“调课通知增强”'),
            content: const Text(
              '开启后，应用会将你的学号、教务系统加密密码和当前学期发送到所配置的调课服务，用于代你查询调课通知，并在后台刷新受影响周。\n\n'
              '普通课表和桌面小组件不依赖此服务。继续后还会申请通知权限，并引导你设置电池优化和自启动。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('保持关闭'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('我已了解，继续'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _prepareBackgroundPolling() async {
    if (!await _confirmPollingConsent()) return false;
    if (!await LocalNotifications.ensurePermission()) {
      _showMessage('未授予系统通知权限，无法及时接收调课变更提醒');
      return false;
    }
    final ignored =
        await AndroidBackgroundRestrictions.isIgnoringBatteryOptimizations();
    if (ignored != true) {
      final opened =
          await AndroidBackgroundRestrictions.requestIgnoreBatteryOptimizations();
      if (!opened) {
        await AndroidBackgroundRestrictions.openBatteryOptimizationSettings();
      }
    }
    await AndroidBackgroundRestrictions.openAutoStartSettings();
    if (!mounted) return false;
    _showMessage('已尝试完成后台运行设置，稳定性将根据后续运行情况自动判断');
    return true;
  }

  Future<void> _togglePolling(bool value) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (value) {
        final prepared = await _prepareBackgroundPolling();
        if (!prepared || !mounted) return;
        await ScheduleSettingsManager.markNoticePrivacyConsentAccepted();
      }
      await ScheduleUpdateWorker.markEnabledAtIfNeeded(enabled: value);
      await _manager.save(
        showWeekend: _manager.showWeekend,
        timeInfoEnabled: _manager.timeInfoEnabled,
        backgroundPollingEnabled: value,
        noticeApiBaseUrl: _manager.noticeApiBaseUrl,
      );
      await ScheduleUpdateWorker.syncFromPreferences();
      final health = await ScheduleUpdateWorker.loadHealthSnapshot();
      if (!mounted) return;
      setState(() {
        _pollingEnabled = value;
        _health = health;
      });
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  String? _validateServiceUrl(String value) {
    if (value.trim().isEmpty) return null;
    return ScheduleSettingsManager.isValidNoticeApiBaseUrl(value)
        ? null
        : '请输入不含路径的 HTTPS 服务地址';
  }

  Future<void> _saveServiceUrl() async {
    final value = _serviceController.text.trim();
    final error = _validateServiceUrl(value);
    if (error != null) {
      setState(() => _serviceError = error);
      return;
    }
    final normalized = ScheduleSettingsManager.normalizeNoticeApiBaseUrl(value);
    await _manager.save(
      showWeekend: _manager.showWeekend,
      timeInfoEnabled: _manager.timeInfoEnabled,
      backgroundPollingEnabled: _pollingEnabled,
      noticeApiBaseUrl: normalized,
    );
    if (!mounted) return;
    setState(() => _serviceError = null);
    _showMessage('调课服务地址已保存');
  }

  Future<void> _testConnectivity() async {
    final value = _serviceController.text.trim();
    final error = _validateServiceUrl(value);
    if (error != null) {
      setState(() => _serviceError = error);
      return;
    }
    setState(() {
      _testingConnectivity = true;
      _connectivityMessage = '正在测试…';
    });
    final result = await NoticeApi.testConnectivity(value);
    if (!mounted) return;
    setState(() {
      _testingConnectivity = false;
      _connectivityMessage = '${result.message}（${result.elapsedMs}ms）';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知与提醒')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text('课程提醒', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('课前提醒'),
                        subtitle: const Text('自动重建未来 60 天的课程提醒'),
                        value: _remindersEnabled,
                        onChanged: _working ? null : _toggleReminders,
                      ),
                      if (_remindersEnabled) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: AppSelectField<int>(
                            value: _reminderMinutes,
                            labelText: '默认提前时间',
                            sheetTitle: '选择默认提前时间',
                            options: const [
                              AppSelectOption(value: 5, label: '提前 5 分钟'),
                              AppSelectOption(value: 10, label: '提前 10 分钟'),
                              AppSelectOption(value: 15, label: '提前 15 分钟'),
                              AppSelectOption(value: 30, label: '提前 30 分钟'),
                            ],
                            onChanged: _working ? null : _changeReminderMinutes,
                          ),
                        ),
                      ],
                      if (_remindersEnabled && !_exactAlarmGranted)
                        const ListTile(
                          leading: Icon(Icons.warning_amber_rounded),
                          title: Text('精确闹钟权限尚未生效'),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('调课通知', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('调课通知增强'),
                        subtitle: Text(
                          !_pollingEnabled
                              ? '关闭时不会访问调课服务'
                              : _health == null
                              ? '后台检查调课通知'
                              : '${_health!.title} · ${_health!.detail}',
                        ),
                        value: _pollingEnabled,
                        onChanged: _working ? null : _togglePolling,
                      ),
                      ExpansionTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('高级设置'),
                        subtitle: const Text('自定义调课服务地址'),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        children: [
                          TextField(
                            controller: _serviceController,
                            keyboardType: TextInputType.url,
                            decoration: InputDecoration(
                              labelText: '调课服务地址',
                              hintText: ScheduleSettingsManager
                                  .officialNoticeApiBaseUrl,
                              helperText: '留空使用官方服务，仅支持 HTTPS',
                              errorText: _serviceError,
                            ),
                            onChanged: (_) {
                              if (_serviceError != null) {
                                setState(() => _serviceError = null);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _testingConnectivity
                                      ? null
                                      : _testConnectivity,
                                  child: Text(
                                    _testingConnectivity ? '测试中…' : '测试连通性',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _saveServiceUrl,
                                  child: const Text('保存地址'),
                                ),
                              ),
                            ],
                          ),
                          if (_connectivityMessage.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_connectivityMessage),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
