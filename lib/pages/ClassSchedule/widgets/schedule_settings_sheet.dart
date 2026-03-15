import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cqut/utils/android_background_restrictions.dart';

class ScheduleSettingsSheet extends StatefulWidget {
  final bool initialShowWeekend;
  final bool initialTimeInfoEnabled;
  final bool initialUpdateShowDiff;
  final bool initialBackgroundPollingEnabled;
  final Function({
    required bool showWeekend,
    required bool timeInfoEnabled,
    required bool updateShowDiff,
    required bool backgroundPollingEnabled,
  })
  onSave;

  const ScheduleSettingsSheet({
    super.key,
    required this.initialShowWeekend,
    required this.initialTimeInfoEnabled,
    required this.initialUpdateShowDiff,
    required this.initialBackgroundPollingEnabled,
    required this.onSave,
  });

  @override
  State<ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<ScheduleSettingsSheet> {
  late bool showWeekend;
  late bool timeInfoEnabled;
  late bool showDiff;
  late bool backgroundPollingEnabled;
  bool confirmDialogOpen = false;
  bool _allowPop = false;

  late bool _baselineShowWeekend;
  late bool _baselineTimeInfoEnabled;
  late bool _baselineShowDiff;
  late bool _baselineBackgroundPollingEnabled;

  @override
  void initState() {
    super.initState();
    showWeekend = widget.initialShowWeekend;
    timeInfoEnabled = widget.initialTimeInfoEnabled;
    showDiff = widget.initialUpdateShowDiff;
    backgroundPollingEnabled = widget.initialBackgroundPollingEnabled;

    _baselineShowWeekend = showWeekend;
    _baselineTimeInfoEnabled = timeInfoEnabled;
    _baselineShowDiff = showDiff;
    _baselineBackgroundPollingEnabled = backgroundPollingEnabled;
  }

  bool hasUnsavedChanges() {
    return showWeekend != _baselineShowWeekend ||
        timeInfoEnabled != _baselineTimeInfoEnabled ||
        showDiff != _baselineShowDiff ||
        backgroundPollingEnabled != _baselineBackgroundPollingEnabled;
  }

  Future<bool> _ensureBackgroundPollingPermissions(BuildContext context) async {
    final ignored =
        await AndroidBackgroundRestrictions.isIgnoringBatteryOptimizations();
    if (ignored != true) {
      await AndroidBackgroundRestrictions.requestIgnoreBatteryOptimizations();
      final after =
          await AndroidBackgroundRestrictions.isIgnoringBatteryOptimizations();
      if (after != true) {
        if (!context.mounted) return false;
        final proceed =
            await showDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text('需要忽略电池优化'),
                  content: Text('后台轮询需要忽略电池优化，请先授权后再开启。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('去设置'),
                    ),
                  ],
                );
              },
            ) ??
            false;
        if (!proceed) return false;
        await AndroidBackgroundRestrictions.openBatteryOptimizationSettings();
        if (!context.mounted) return false;
        final confirmed =
            await showDialog<bool>(
              context: context,
              builder: (context) {
                return AlertDialog(
                  title: Text('授权确认'),
                  content: Text('完成忽略电池优化后，点击“已完成”。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('已完成'),
                    ),
                  ],
                );
              },
            ) ??
            false;
        if (!confirmed) return false;
      }
    }

    if (!context.mounted) return false;
    final openAutoStart =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('开启自启动'),
              content: Text('请在系统页面中允许应用自启动，以提升后台轮询稳定性。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('去开启'),
                ),
              ],
            );
          },
        ) ??
        false;
    if (!openAutoStart) return false;
    await AndroidBackgroundRestrictions.openAutoStartSettings();
    if (!context.mounted) return false;
    final done =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('确认已开启'),
              content: Text('完成自启动授权后，点击“已开启”。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('已开启'),
                ),
              ],
            );
          },
        ) ??
        false;
    return done;
  }

  Future<bool> saveSettings() async {
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'schedule_toggle_show_weekend',
        parameters: {'value': showWeekend ? 1 : 0},
      ),
    );

    widget.onSave(
      showWeekend: showWeekend,
      timeInfoEnabled: timeInfoEnabled,
      updateShowDiff: showDiff,
      backgroundPollingEnabled: backgroundPollingEnabled,
    );

    if (mounted) {
      setState(() {
        _baselineShowWeekend = showWeekend;
        _baselineTimeInfoEnabled = timeInfoEnabled;
        _baselineShowDiff = showDiff;
        _baselineBackgroundPollingEnabled = backgroundPollingEnabled;
      });
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
                  SwitchListTile(
                    title: Text('变更提示显示详情'),
                    subtitle: Text('提示具体变化课程以及变化详情'),
                    value: showDiff,
                    onChanged: (value) {
                      setState(() {
                        showDiff = value;
                      });
                    },
                  ),
                  SwitchListTile(
                    title: Text('启用后台定时轮询'),
                    subtitle: Text('后台定时检查调课通知并更新受影响周课表'),
                    value: backgroundPollingEnabled,
                    onChanged: (value) async {
                      if (value && !backgroundPollingEnabled) {
                        final ok = await _ensureBackgroundPollingPermissions(
                          context,
                        );
                        if (!ok) return;
                      }
                      setState(() {
                        backgroundPollingEnabled = value;
                      });
                    },
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
                            onPressed: () async {
                              final ok = await saveSettings();
                              if (!ok) return;
                              if (!context.mounted) return;
                              _requestClose();
                            },
                            child: Text('保存'),
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
  required bool initialUpdateShowDiff,
  required bool initialBackgroundPollingEnabled,
  required Function({
    required bool showWeekend,
    required bool timeInfoEnabled,
    required bool updateShowDiff,
    required bool backgroundPollingEnabled,
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
        initialUpdateShowDiff: initialUpdateShowDiff,
        initialBackgroundPollingEnabled: initialBackgroundPollingEnabled,
        onSave: onSave,
      );
    },
  );
}
