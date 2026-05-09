import 'dart:async';
import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:cqut_helper/utils/local_notifications.dart';

class ScheduleSettingsSheet extends StatefulWidget {
  final bool initialShowWeekend;
  final bool initialTimeInfoEnabled;
  final bool initialBackgroundPollingEnabled;
  final String initialNoticeApiBaseUrl;
  final Future<void> Function({
    required bool showWeekend,
    required bool timeInfoEnabled,
    required bool backgroundPollingEnabled,
    required String noticeApiBaseUrl,
  })
  onSave;

  const ScheduleSettingsSheet({
    super.key,
    required this.initialShowWeekend,
    required this.initialTimeInfoEnabled,
    required this.initialBackgroundPollingEnabled,
    required this.initialNoticeApiBaseUrl,
    required this.onSave,
  });

  @override
  State<ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<ScheduleSettingsSheet> {
  late bool showWeekend;
  late bool timeInfoEnabled;
  late bool backgroundPollingEnabled;
  late TextEditingController _noticeApiController;
  late String noticeApiBaseUrl;
  String? _noticeApiError;
  bool _testingConnectivity = false;
  bool? _connectivityOk;
  String _connectivityMessage = '';
  String _sheetNoticeMessage = '';
  int? _connectivityElapsedMs;
  bool _noticeConfigExpanded = false;
  bool confirmDialogOpen = false;
  bool _allowPop = false;
  bool _checkingSetup = false;
  ScheduleBackgroundPollHealthSnapshot? _healthSnapshot;

  late bool _baselineShowWeekend;
  late bool _baselineTimeInfoEnabled;
  late bool _baselineBackgroundPollingEnabled;
  late String _baselineNoticeApiBaseUrl;

  @override
  void initState() {
    super.initState();
    showWeekend = widget.initialShowWeekend;
    timeInfoEnabled = widget.initialTimeInfoEnabled;
    backgroundPollingEnabled = widget.initialBackgroundPollingEnabled;
    final normalizedInitialBaseUrl =
        ScheduleSettingsManager.normalizeNoticeApiBaseUrl(
          widget.initialNoticeApiBaseUrl,
        );
    noticeApiBaseUrl =
        normalizedInitialBaseUrl ==
            ScheduleSettingsManager.officialNoticeApiBaseUrl
        ? ''
        : normalizedInitialBaseUrl;
    _noticeApiController = TextEditingController(text: noticeApiBaseUrl);
    _noticeApiController.addListener(() {
      final next = _noticeApiController.text.trim();
      setState(() {
        noticeApiBaseUrl = next;
        _noticeApiError = _validateNoticeApiBaseUrl(next);
      });
    });
    _noticeApiError = _validateNoticeApiBaseUrl(noticeApiBaseUrl);

    _baselineShowWeekend = showWeekend;
    _baselineTimeInfoEnabled = timeInfoEnabled;
    _baselineBackgroundPollingEnabled = backgroundPollingEnabled;
    _baselineNoticeApiBaseUrl = noticeApiBaseUrl;
    unawaited(_loadHealthSnapshot());
  }

  @override
  void dispose() {
    _noticeApiController.dispose();
    super.dispose();
  }

  bool hasUnsavedChanges() {
    return showWeekend != _baselineShowWeekend ||
        timeInfoEnabled != _baselineTimeInfoEnabled ||
        backgroundPollingEnabled != _baselineBackgroundPollingEnabled ||
        ScheduleSettingsManager.normalizeNoticeApiBaseUrl(noticeApiBaseUrl) !=
            ScheduleSettingsManager.normalizeNoticeApiBaseUrl(
              _baselineNoticeApiBaseUrl,
            );
  }

  String? _validateNoticeApiBaseUrl(String value) {
    if (value.trim().isEmpty) return null;
    if (!ScheduleSettingsManager.isValidNoticeApiBaseUrl(value)) {
      return '请输入合法域名，例如 https://mydomain.com';
    }
    return null;
  }

  Future<void> _loadHealthSnapshot() async {
    final snapshot = await ScheduleUpdateWorker.loadHealthSnapshot();
    if (!mounted) return;
    setState(() {
      _healthSnapshot = snapshot;
    });
  }

  Future<void> _testConnectivity() async {
    final error = _validateNoticeApiBaseUrl(noticeApiBaseUrl);
    if (error != null) {
      setState(() {
        _noticeApiError = error;
        _connectivityOk = false;
        _connectivityElapsedMs = null;
        _connectivityMessage = '请先修正域名格式';
      });
      return;
    }
    setState(() {
      _testingConnectivity = true;
      _connectivityMessage = '正在检测连通性...';
      _connectivityElapsedMs = null;
      _connectivityOk = null;
    });
    final result = await NoticeApi.testConnectivity(noticeApiBaseUrl);
    if (!mounted) return;
    setState(() {
      _testingConnectivity = false;
      _connectivityOk = result.success;
      _connectivityElapsedMs = result.elapsedMs;
      _connectivityMessage = result.message;
    });
  }

  Future<bool> _runBackgroundPollingSetupFlow() async {
    if (!mounted) return false;
    final proceed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('启用后台定时轮询'),
              content: const Text(
                '启用后会在后台定时检查调课通知。为提升稳定性，建议授予通知权限、忽略电池优化，并在系统中允许应用自启动。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('暂不开启'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('继续开启'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!proceed) return false;

    final granted = await LocalNotifications.ensurePermission();
    if (!mounted) return false;
    if (!granted) {
      setState(() {
        _sheetNoticeMessage = '未授予系统通知权限，无法及时接收调课变更提醒。';
      });
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
    if (!mounted) return false;

    await AndroidBackgroundRestrictions.openAutoStartSettings();
    if (!mounted) return false;

    setState(() {
      _sheetNoticeMessage = ignored == true
          ? '已检测到忽略电池优化；已尝试打开自启动设置，后续会根据后台运行情况自动判断稳定性。'
          : '已尝试打开电池优化与自启动相关设置；后台轮询仍可开启，实际稳定性以后续后台运行记录为准。';
    });
    return true;
  }

  Future<void> _onBackgroundPollingSwitchChanged(bool value) async {
    if (!value) {
      setState(() {
        backgroundPollingEnabled = false;
        _noticeConfigExpanded = false;
        _sheetNoticeMessage = '';
      });
      return;
    }

    if (backgroundPollingEnabled || _checkingSetup) return;
    setState(() {
      _checkingSetup = true;
    });
    try {
      final ok = await _runBackgroundPollingSetupFlow();
      if (!mounted) return;
      if (!ok) {
        setState(() {
          backgroundPollingEnabled = false;
        });
        return;
      }
      setState(() {
        backgroundPollingEnabled = true;
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingSetup = false;
        });
      }
    }
  }

  Future<bool> saveSettings() async {
    final error = _validateNoticeApiBaseUrl(noticeApiBaseUrl);
    if (error != null) {
      setState(() {
        _noticeApiError = error;
        _sheetNoticeMessage = error;
      });
      return false;
    }

    final normalizedBaseUrl = ScheduleSettingsManager.normalizeNoticeApiBaseUrl(
      noticeApiBaseUrl,
    );
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'schedule_toggle_show_weekend',
        parameters: {'value': showWeekend ? 1 : 0},
      ),
    );

    await ScheduleUpdateWorker.markEnabledAtIfNeeded(
      enabled: backgroundPollingEnabled,
    );

    await widget.onSave(
      showWeekend: showWeekend,
      timeInfoEnabled: timeInfoEnabled,
      backgroundPollingEnabled: backgroundPollingEnabled,
      noticeApiBaseUrl: normalizedBaseUrl,
    );

    if (mounted) {
      setState(() {
        _baselineShowWeekend = showWeekend;
        _baselineTimeInfoEnabled = timeInfoEnabled;
        _baselineBackgroundPollingEnabled = backgroundPollingEnabled;
        noticeApiBaseUrl = normalizedBaseUrl;
        _baselineNoticeApiBaseUrl = normalizedBaseUrl;
      });
      unawaited(_loadHealthSnapshot());
    }

    return true;
  }

  void _requestClose() {
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    });
  }

  Future<void> maybeConfirmAndClose() async {
    if (confirmDialogOpen) return;
    if (!hasUnsavedChanges()) {
      _requestClose();
      return;
    }

    confirmDialogOpen = true;
    try {
      if (!mounted) return;
      final shouldSave = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text('未保存的更改'),
            content: Text('是否保存课表设置的修改？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('不保存'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('保存'),
              ),
            ],
          );
        },
      );
      if (shouldSave == null) return;

      if (shouldSave) {
        final ok = await saveSettings();
        if (!ok) return;
      }

      _requestClose();
    } finally {
      confirmDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop || !hasUnsavedChanges(),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        maybeConfirmAndClose();
      },
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            bottom: 12 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sheetNoticeMessage.trim().isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _sheetNoticeMessage,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  SwitchListTile(
                    title: Text('显示周末'),
                    subtitle: Text('关闭后仅显示周一到周五'),
                    value: showWeekend,
                    onChanged: (value) {
                      setState(() {
                        showWeekend = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: Text('显示上课时间'),
                    subtitle: Text('关闭后将不会展示课程时间'),
                    value: timeInfoEnabled,
                    onChanged: (value) {
                      setState(() {
                        timeInfoEnabled = value;
                      });
                    },
                  ),
                  ListTile(
                    title: Text('启用后台定时轮询'),
                    subtitle: Text(
                      _healthSnapshot == null
                          ? '后台定时检查调课通知并更新受影响周课表'
                          : '${_healthSnapshot!.title} · ${_healthSnapshot!.detail}',
                    ),
                    onTap: () {
                      if (!backgroundPollingEnabled) return;
                      setState(() {
                        _noticeConfigExpanded = !_noticeConfigExpanded;
                      });
                    },
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (backgroundPollingEnabled)
                          Container(
                            width: 1,
                            height: 20,
                            color: Theme.of(context).dividerColor,
                          ),
                        if (backgroundPollingEnabled) const SizedBox(width: 10),
                        Switch(
                          value: backgroundPollingEnabled,
                          onChanged: _checkingSetup
                              ? null
                              : _onBackgroundPollingSwitchChanged,
                        ),
                      ],
                    ),
                  ),
                  if (backgroundPollingEnabled && _noticeConfigExpanded)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _noticeApiController,
                            keyboardType: TextInputType.url,
                            textInputAction: TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: '调课信息接口域名',
                              hintText: ScheduleSettingsManager
                                  .officialNoticeApiBaseUrl,
                              helperText: '留空使用官方域名；仅支持 http/https 且不包含路径',
                              errorText: _noticeApiError,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              FilledButton.tonal(
                                onPressed: _testingConnectivity
                                    ? null
                                    : _testConnectivity,
                                child: Text(
                                  _testingConnectivity ? '测试中...' : '测试连通性',
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _connectivityMessage.isEmpty
                                      ? '输入后可测试 /health 接口连通性'
                                      : _connectivityElapsedMs == null
                                      ? _connectivityMessage
                                      : '$_connectivityMessage（${_connectivityElapsedMs}ms）',
                                  style: TextStyle(
                                    color: _connectivityOk == null
                                        ? Theme.of(context).hintColor
                                        : _connectivityOk == true
                                        ? Colors.green
                                        : Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: maybeConfirmAndClose,
                            child: Text('取消'),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _checkingSetup
                                ? null
                                : () async {
                                    final ok = await saveSettings();
                                    if (!ok) return;
                                    if (!context.mounted) return;
                                    _requestClose();
                                  },
                            child: Text(_checkingSetup ? '检查中...' : '保存'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void showScheduleSettingsSheet(
  BuildContext context, {
  required bool initialShowWeekend,
  required bool initialTimeInfoEnabled,
  required bool initialBackgroundPollingEnabled,
  required String initialNoticeApiBaseUrl,
  required Future<void> Function({
    required bool showWeekend,
    required bool timeInfoEnabled,
    required bool backgroundPollingEnabled,
    required String noticeApiBaseUrl,
  })
  onSave,
}) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return ScheduleSettingsSheet(
        initialShowWeekend: initialShowWeekend,
        initialTimeInfoEnabled: initialTimeInfoEnabled,
        initialBackgroundPollingEnabled: initialBackgroundPollingEnabled,
        initialNoticeApiBaseUrl: initialNoticeApiBaseUrl,
        onSave: onSave,
      );
    },
  );
}
