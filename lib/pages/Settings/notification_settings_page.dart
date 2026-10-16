import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/course_reminder_mode.dart';
import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:cqut_helper/widgets/app_select_field.dart';
import 'package:cqut_helper/widgets/background_polling_setup_dialog.dart';
import 'package:cqut_helper/widgets/marquee_text.dart';
import 'package:cqut_helper/widgets/notice_service_risk_dialog.dart';
import 'package:material_ui/material_ui.dart';

import 'settings_schedule_scope.dart';

class NotificationSettingsPage extends StatefulWidget {
  final SettingsScheduleScope scope;

  const NotificationSettingsPage({super.key, required this.scope});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage>
    with WidgetsBindingObserver {
  final ScheduleSettingsManager _manager = ScheduleSettingsManager();
  final TextEditingController _serviceController = TextEditingController();
  bool _loading = true;
  bool _working = false;
  bool _remindersEnabled = false;
  int _reminderMinutes = 10;
  bool _reminderAtStart = false;
  CourseAutoMode _courseAutoMode = CourseAutoMode.off;
  CourseReminderPermissionStatus? _permissionStatus;
  bool _permissionStatusLoadFailed = false;
  bool _permissionRefreshInProgress = false;
  CourseAutoMode? _pendingCourseAutoMode;
  String? _pendingPermissionKind;
  bool _pollingEnabled = false;
  ScheduleBackgroundPollHealthSnapshot? _health;
  String? _serviceError;
  String _availabilityMessage = '';
  bool _testingAvailability = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _serviceController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshPermissionStatus();
  }

  Future<void> _load() async {
    await _manager.load();
    CourseReminderPermissionStatus? permissionStatus;
    try {
      permissionStatus = await CourseReminderMode.getStatus();
    } catch (_) {
      _permissionStatusLoadFailed = true;
    }
    final health = await ScheduleUpdateWorker.loadHealthSnapshot();
    if (!mounted) return;
    final serviceUrl = _manager.noticeApiBaseUrl;
    _serviceController.text =
        serviceUrl == ScheduleSettingsManager.officialNoticeApiBaseUrl
        ? ''
        : serviceUrl;
    setState(() {
      _remindersEnabled = _manager.remindersEnabled;
      _reminderMinutes = _manager.defaultReminderMinutes;
      _reminderAtStart = _manager.defaultReminderAtStart;
      _courseAutoMode = _manager.courseAutoMode;
      _permissionStatus = permissionStatus;
      _permissionStatusLoadFailed = permissionStatus == null;
      _pollingEnabled = _manager.backgroundPollingEnabled;
      _health = health;
      _loading = false;
    });
  }

  Future<void> _refreshPermissionStatus({
    bool rebuildOnPermissionChange = true,
  }) async {
    if (_permissionRefreshInProgress) return;
    _permissionRefreshInProgress = true;
    try {
      CourseReminderPermissionStatus? status;
      try {
        status = await CourseReminderMode.getStatus();
      } catch (_) {}
      if (!mounted) return;
      final previous = _permissionStatus;
      final changed =
          status != null &&
          (previous == null
              ? status.supported
              : previous.notificationGranted != status.notificationGranted ||
                    previous.exactAlarmGranted != status.exactAlarmGranted ||
                    previous.dndGranted != status.dndGranted ||
                    previous.batteryOptimizationIgnored !=
                        status.batteryOptimizationIgnored);
      setState(() {
        if (status != null) _permissionStatus = status;
        _permissionStatusLoadFailed = status == null;
      });
      final pendingMode = _pendingCourseAutoMode;
      if (pendingMode != null) {
        if (status == null) {
          _clearPendingCourseAutoMode('无法读取系统授权状态，课程模式未更改；可以重试。');
          return;
        }
        await _continuePendingCourseAutoMode(pendingMode, status);
        return;
      }
      if (rebuildOnPermissionChange &&
          changed &&
          _remindersEnabled &&
          widget.scope.userId.isNotEmpty) {
        try {
          await CourseReminderScheduler.rescheduleForUser(widget.scope.userId);
        } catch (error) {
          _showMessage('权限状态已刷新，但重建课程提醒失败：$error');
        }
      }
    } finally {
      _permissionRefreshInProgress = false;
    }
  }

  String? _missingCourseModePermission(CourseReminderPermissionStatus status) {
    if (!status.dndGranted) return 'dnd';
    if (!status.exactAlarmGranted) return 'exactAlarm';
    return null;
  }

  bool _permissionGranted(CourseReminderPermissionStatus status, String kind) =>
      switch (kind) {
        'dnd' => status.dndGranted,
        'exactAlarm' => status.exactAlarmGranted,
        _ => false,
      };

  Future<bool> _confirmCourseModePermission(String kind) async {
    final isDnd = kind == 'dnd';
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(isDnd ? '需要勿扰权限' : '需要精确闹钟权限'),
            content: Text(
              isDnd
                  ? '要在课程期间自动切换勿扰或静音，需要允许应用访问系统勿扰设置。课程开始时会切换，课程结束后恢复原系统状态。'
                  : '需要精确闹钟权限，才能按已同步课程时间准确触发提醒并切换勿扰或静音。',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('去设置'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _openCourseModePermission(String kind) async {
    if (!await _confirmCourseModePermission(kind)) return false;
    try {
      if (await CourseReminderMode.openSettings(kind)) return true;
      _showMessage('无法打开对应的系统设置，课程模式未更改。');
      return false;
    } catch (error) {
      _showMessage('打开系统设置失败，课程模式未更改：$error');
      return false;
    }
  }

  Future<void> _continuePendingCourseAutoMode(
    CourseAutoMode requestedMode,
    CourseReminderPermissionStatus status,
  ) async {
    if (!status.supported) {
      _clearPendingCourseAutoMode('此设备不支持课程勿扰与静音，设置未更改。');
      return;
    }
    final missingKind = _missingCourseModePermission(status);
    if (missingKind == null) {
      _pendingCourseAutoMode = null;
      _pendingPermissionKind = null;
      try {
        await _applyCourseAutoMode(requestedMode);
      } catch (error) {
        _showMessage(
          _courseAutoMode == requestedMode
              ? '上课勿扰与静音已保存，但课程提醒计划更新失败：$error'
              : '应用上课勿扰与静音失败，原设置未更改：$error',
        );
      } finally {
        if (mounted) setState(() => _working = false);
      }
      return;
    }
    final previousKind = _pendingPermissionKind;
    if (previousKind != null && !_permissionGranted(status, previousKind)) {
      _clearPendingCourseAutoMode('系统授权未完成，课程模式保持原设置；可以重试。');
      return;
    }
    _pendingPermissionKind = missingKind;
    if (await _openCourseModePermission(missingKind)) return;
    _clearPendingCourseAutoMode('系统授权流程已取消，课程模式保持原设置；可以重试。');
  }

  void _clearPendingCourseAutoMode(String message) {
    _pendingCourseAutoMode = null;
    _pendingPermissionKind = null;
    if (mounted) setState(() => _working = false);
    _showMessage(message);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _persistReminderSettings({
    bool? remindersEnabled,
    int? reminderMinutes,
    bool? reminderAtStart,
    CourseAutoMode? courseAutoMode,
  }) async {
    await _manager.saveReminderSettings(
      remindersEnabled: remindersEnabled ?? _remindersEnabled,
      defaultReminderMinutes: reminderMinutes ?? _reminderMinutes,
      defaultReminderAtStart: reminderAtStart ?? _reminderAtStart,
      courseAutoMode: courseAutoMode ?? _courseAutoMode,
    );
  }

  Future<void> _rescheduleReminders() async {
    if (_remindersEnabled && widget.scope.userId.isNotEmpty) {
      await CourseReminderScheduler.rescheduleForUser(widget.scope.userId);
    } else {
      await CourseReminderScheduler.cancelAll();
    }
  }

  Future<void> _toggleReminders(bool value) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      if (value &&
          !await LocalNotifications.ensureCourseReminderPermissions()) {
        if (!mounted) return;
        _showMessage('当前未同时获得通知和精确闹钟权限；请允许通知及“闹钟与提醒”，再重试。');
        return;
      }
      if (!mounted) return;
      await _persistReminderSettings(remindersEnabled: value);
      if (!mounted) return;
      setState(() => _remindersEnabled = value);
      await _rescheduleReminders();
      await _refreshPermissionStatus(rebuildOnPermissionChange: false);
    } catch (error) {
      _showMessage('保存或重建课程提醒失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changeReminderChoice(int value) async {
    if (value == -1) {
      final minutes = await _showCustomReminderDialog();
      if (minutes != null) await _saveReminderChoice(minutes);
      return;
    }
    await _saveReminderChoice(value);
  }

  Future<void> _saveReminderChoice(int value) async {
    if (_working) return;
    final atStart = value == 0;
    final minutes = atStart ? _reminderMinutes : value;
    setState(() => _working = true);
    try {
      await _persistReminderSettings(
        reminderMinutes: minutes,
        reminderAtStart: atStart,
      );
      if (!mounted) return;
      setState(() {
        _reminderMinutes = minutes;
        _reminderAtStart = atStart;
      });
      await _rescheduleReminders();
    } on ArgumentError {
      _showMessage('提前时间必须在 1 到 120 分钟之间');
    } catch (error) {
      _showMessage('保存或重建课程提醒失败：$error');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<int?> _showCustomReminderDialog() async {
    final formKey = GlobalKey<FormState>();
    final fieldKey = GlobalKey<FormFieldState<String>>();
    final result = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('自定义提前时间'),
        content: Form(
          key: formKey,
          child: TextFormField(
            key: fieldKey,
            initialValue: '$_reminderMinutes',
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: '提前分钟数',
              suffixText: '分钟',
            ),
            validator: (raw) {
              final value = int.tryParse((raw ?? '').trim());
              if (value == null || value < 1 || value > 120) {
                return '请输入 1 到 120 之间的整数';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() != true) return;
              Navigator.pop(
                dialogContext,
                int.parse(fieldKey.currentState!.value!.trim()),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
    return result;
  }

  Future<void> _changeCourseAutoMode(CourseAutoMode value) async {
    if (_working || _permissionRefreshInProgress) return;
    setState(() => _working = true);
    try {
      if (value == CourseAutoMode.off) {
        await _applyCourseAutoMode(value);
        await _refreshPermissionStatus(rebuildOnPermissionChange: false);
        return;
      }
      final status = await CourseReminderMode.getStatus();
      if (!mounted) return;
      setState(() {
        _permissionStatus = status;
        _permissionStatusLoadFailed = false;
      });
      if (!status.supported) {
        _showMessage('此设备不支持课程勿扰与静音，原设置未更改。');
        return;
      }
      final missingKind = _missingCourseModePermission(status);
      if (missingKind == null) {
        await _applyCourseAutoMode(value);
        return;
      }
      _pendingCourseAutoMode = value;
      _pendingPermissionKind = missingKind;
      if (!await _openCourseModePermission(missingKind)) {
        _clearPendingCourseAutoMode('系统授权流程已取消，课程模式保持原设置；可以重试。');
      }
    } catch (error) {
      _pendingCourseAutoMode = null;
      _pendingPermissionKind = null;
      _showMessage(
        _courseAutoMode == value
            ? '上课勿扰与静音已保存，但应用失败：$error'
            : '读取授权或应用上课模式失败，原设置未更改：$error',
      );
    } finally {
      if (mounted && _pendingCourseAutoMode == null) {
        setState(() => _working = false);
      }
    }
  }

  Future<void> _applyCourseAutoMode(CourseAutoMode value) async {
    await _persistReminderSettings(courseAutoMode: value);
    if (!mounted) return;
    setState(() => _courseAutoMode = value);
    await _rescheduleReminders();
    CourseReminderPermissionStatus? status;
    try {
      status = await CourseReminderMode.getStatus();
    } catch (_) {}
    if (!mounted || status == null) return;
    setState(() {
      _permissionStatus = status;
      _permissionStatusLoadFailed = false;
    });
  }

  Future<void> _openPermissionSettings(String kind) async {
    try {
      if ((kind == 'dnd' || kind == 'exactAlarm') &&
          !await _confirmCourseModePermission(kind)) {
        return;
      }
      if (!await CourseReminderMode.openSettings(kind)) {
        _showMessage('无法打开对应的系统设置');
      }
    } catch (error) {
      _showMessage('打开系统设置失败：$error');
    }
  }

  Future<void> _openBatteryOptimizationSettings() async {
    if (!await AndroidBackgroundRestrictions.openBatteryOptimizationSettings()) {
      _showMessage('无法打开电池优化设置');
    }
  }

  Future<void> _openAutoStartSettings() async {
    if (!await AndroidBackgroundRestrictions.openAutoStartSettings()) {
      _showMessage('当前设备未提供自启动设置入口');
    }
  }

  Future<bool> _confirmPollingConsent() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('开启“调课通知增强”'),
            content: const Text(
              '开启后，应用会将你的学号、教务系统加密密码和当前学期发送到所配置的调课服务，用于代你查询调课通知，并在后台刷新受影响周。\n\n'
              'CQUT Helper 官方调课服务仅使用上述信息完成查询，不会储存你的学号、密码、学期等隐私数据；若使用自定义服务，其数据处理方式由服务提供者决定。\n\n'
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
    if (!mounted) return false;
    return showBackgroundPollingSetupDialog(context);
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
    if (!ScheduleSettingsManager.isOfficialNoticeApiBaseUrl(normalized) &&
        !await confirmCustomNoticeServiceRisk(context)) {
      return;
    }
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

  Future<void> _testAvailability() async {
    final value = _serviceController.text.trim();
    final error = _validateServiceUrl(value);
    if (error != null) {
      setState(() => _serviceError = error);
      return;
    }
    setState(() {
      _testingAvailability = true;
      _availabilityMessage = '正在调用调课服务…';
    });
    NoticeApiAvailabilityResult result;
    try {
      final encryptedPassword =
          ((await CredentialStore().readEncryptedPassword()) ?? '').trim();
      result = await NoticeApi().testAvailability(
        baseUrl: value,
        username: widget.scope.userId,
        encryptedPassword: encryptedPassword,
        yearTerm: widget.scope.yearTerm,
      );
    } catch (_) {
      result = const NoticeApiAvailabilityResult(
        success: false,
        elapsedMs: 0,
        message: '读取登录凭据失败，请重新登录后再检查',
      );
    }
    if (!mounted) return;
    setState(() {
      _testingAvailability = false;
      _availabilityMessage = '${result.message}（${result.elapsedMs}ms）';
    });
  }

  Widget _permissionTile({
    required IconData icon,
    required String title,
    required bool granted,
    required String kind,
    String grantedLabel = '已授权',
    String deniedLabel = '未授权',
    Future<void> Function()? onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(granted ? grantedLabel : deniedLabel),
      trailing: TextButton(
        onPressed: onTap ?? () => _openPermissionSettings(kind),
        child: const Text('去设置'),
      ),
    );
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
                        subtitle: const Text('按已同步课表提醒即将开始的课程'),
                        value: _remindersEnabled,
                        onChanged: _working ? null : _toggleReminders,
                      ),
                      const Divider(height: 1),
                      const ListTile(
                        leading: Icon(Icons.info_outline),
                        title: Text('提醒时间依据已同步课表和学校作息'),
                      ),
                      if (_remindersEnabled) ...[
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: AppSelectField<int>(
                            value: _reminderAtStart ? 0 : _reminderMinutes,
                            labelText: '默认提前时间',
                            sheetTitle: '选择课程提醒时间',
                            options: [
                              AppSelectOption(value: 5, label: '提前 5 分钟'),
                              AppSelectOption(value: 10, label: '提前 10 分钟'),
                              AppSelectOption(value: 15, label: '提前 15 分钟'),
                              AppSelectOption(value: 30, label: '提前 30 分钟'),
                              const AppSelectOption(value: 0, label: '准时'),
                              if (![5, 10, 15, 30].contains(_reminderMinutes))
                                AppSelectOption(
                                  value: _reminderMinutes,
                                  label: '自定义 · $_reminderMinutes 分钟',
                                ),
                              const AppSelectOption(
                                value: -1,
                                label: '自定义…',
                                description: '设置 1 到 120 分钟',
                              ),
                            ],
                            onChanged: _working ? null : _changeReminderChoice,
                          ),
                        ),
                        const Divider(height: 1),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: AppSelectField<CourseAutoMode>(
                            value: _courseAutoMode,
                            labelText: '上课勿扰与静音',
                            sheetTitle: '选择上课勿扰与静音',
                            options: const [
                              AppSelectOption(
                                value: CourseAutoMode.off,
                                label: '关闭',
                                description: '上课时不调整系统模式',
                              ),
                              AppSelectOption(
                                value: CourseAutoMode.dnd,
                                label: '勿扰模式',
                                description: '上课期间开启系统勿扰模式',
                              ),
                              AppSelectOption(
                                value: CourseAutoMode.silent,
                                label: '静音',
                                description: '上课期间将设备设为静音',
                              ),
                            ],
                            onChanged:
                                !_working &&
                                    _permissionStatus?.supported == true
                                ? _changeCourseAutoMode
                                : null,
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.schedule_outlined),
                          title: Text(
                            _permissionStatus?.autoModeStatus ??
                                (_courseAutoMode == CourseAutoMode.off
                                    ? '上课勿扰与静音已关闭'
                                    : '等待状态更新'),
                          ),
                          subtitle: const Text('课程结束后恢复原系统状态'),
                        ),
                        if (_courseAutoMode != CourseAutoMode.off &&
                            _permissionStatus?.supported == true &&
                            !_permissionStatus!.dndGranted)
                          ListTile(
                            leading: const Icon(Icons.do_not_disturb_on),
                            title: const Text('需要勿扰权限'),
                            subtitle: const Text('允许应用管理系统勿扰模式'),
                            trailing: TextButton(
                              onPressed: () => _openPermissionSettings('dnd'),
                              child: const Text('去设置'),
                            ),
                          ),
                      ],
                      if (_permissionStatus?.supported == true) ...[
                        const Divider(height: 1),
                        _permissionTile(
                          icon: Icons.notifications_outlined,
                          title: '通知权限',
                          granted: _permissionStatus!.notificationGranted,
                          kind: 'notifications',
                        ),
                        _permissionTile(
                          icon: Icons.alarm,
                          title: '精确闹钟',
                          granted: _permissionStatus!.exactAlarmGranted,
                          kind: 'exactAlarm',
                        ),
                        _permissionTile(
                          icon: Icons.do_not_disturb_on_outlined,
                          title: '勿扰权限',
                          granted: _permissionStatus!.dndGranted,
                          kind: 'dnd',
                        ),
                        _permissionTile(
                          icon: Icons.battery_saver_outlined,
                          title: '电池优化',
                          kind: 'appDetails',
                          granted:
                              _permissionStatus!.batteryOptimizationIgnored,
                          grantedLabel: '已忽略优化',
                          deniedLabel: '可能限制后台提醒',
                          onTap: _openBatteryOptimizationSettings,
                        ),
                        ListTile(
                          leading: const Icon(Icons.rocket_launch_outlined),
                          title: const Text('自启动设置'),
                          subtitle: const Text('部分手机需要允许应用自启动'),
                          trailing: TextButton(
                            onPressed: _openAutoStartSettings,
                            child: const Text('去设置'),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.settings_outlined),
                          title: const Text('应用系统设置'),
                          trailing: TextButton(
                            onPressed: () =>
                                _openPermissionSettings('appDetails'),
                            child: const Text('打开'),
                          ),
                        ),
                      ],
                      if (_permissionStatusLoadFailed)
                        ListTile(
                          leading: const Icon(Icons.sync_problem_outlined),
                          title: const Text('暂时无法读取系统授权状态'),
                          trailing: TextButton(
                            onPressed: _refreshPermissionStatus,
                            child: const Text('重试'),
                          ),
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
                              helper: const MarqueeText(
                                '留空使用官方服务；仅在调课通知增强开启时允许实际查询',
                              ),
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
                                  onPressed:
                                      !_pollingEnabled || _testingAvailability
                                      ? null
                                      : _testAvailability,
                                  child: Text(
                                    !_pollingEnabled
                                        ? '开启后可检查'
                                        : _testingAvailability
                                        ? '检查中…'
                                        : '检查服务可用性',
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
                          if (_availabilityMessage.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(_availabilityMessage),
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
