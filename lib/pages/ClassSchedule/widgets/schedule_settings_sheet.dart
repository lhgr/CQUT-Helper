import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import '../../../utils/android_background_restrictions.dart';
import '../../../utils/local_notifications.dart';
import 'package:cqut/manager/schedule_update_worker.dart';

class ScheduleSettingsSheet extends StatefulWidget {
  final int initialWeeksAhead;
  final bool initialShowWeekend;
  final bool initialUpdateEnabled;
  final int initialUpdateIntervalMinutes;
  final bool initialUpdateShowDiff;
  final bool initialSystemNotifyEnabled;
  final int maxWeeksAhead;
  final Function({
    required int weeksAhead,
    required bool showWeekend,
    required bool updateEnabled,
    required int updateIntervalMinutes,
    required bool updateShowDiff,
    required bool systemNotifyEnabled,
  }) onSave;

  const ScheduleSettingsSheet({
    super.key,
    required this.initialWeeksAhead,
    required this.initialShowWeekend,
    required this.initialUpdateEnabled,
    required this.initialUpdateIntervalMinutes,
    required this.initialUpdateShowDiff,
    required this.initialSystemNotifyEnabled,
    required this.maxWeeksAhead,
    required this.onSave,
  });

  static const String prefsKeyShowWeekend = 'schedule_show_weekend';
  static const String prefsKeyUpdateWeeksAhead = 'schedule_update_weeks_ahead';
  static const String prefsKeyUpdateEnabled = 'schedule_update_enabled';
  static const String prefsKeyUpdateIntervalMinutes =
      'schedule_update_interval_minutes';
  static const String prefsKeyUpdateShowDiff = 'schedule_update_show_diff';
  static const String prefsKeyUpdateSystemNotifyEnabled =
      'schedule_update_system_notification_enabled';

  @override
  State<ScheduleSettingsSheet> createState() => _ScheduleSettingsSheetState();
}

class _ScheduleSettingsSheetState extends State<ScheduleSettingsSheet> {
  late int weeksAhead;
  late bool showWeekend;
  late bool updateEnabled;
  late int intervalMinutes;
  late bool showDiff;
  late bool systemNotifyEnabled;
  bool confirmDialogOpen = false;

  @override
  void initState() {
    super.initState();
    weeksAhead = widget.initialWeeksAhead.clamp(0, widget.maxWeeksAhead);
    showWeekend = widget.initialShowWeekend;
    updateEnabled = widget.initialUpdateEnabled;
    intervalMinutes = widget.initialUpdateIntervalMinutes;
    showDiff = widget.initialUpdateShowDiff;
    systemNotifyEnabled = widget.initialSystemNotifyEnabled;
  }

  bool hasUnsavedChanges() {
    return weeksAhead != widget.initialWeeksAhead ||
        showWeekend != widget.initialShowWeekend ||
        updateEnabled != widget.initialUpdateEnabled ||
        intervalMinutes != widget.initialUpdateIntervalMinutes ||
        showDiff != widget.initialUpdateShowDiff ||
        systemNotifyEnabled != widget.initialSystemNotifyEnabled;
  }

  String _formatIntervalLabel(int minutes) {
    if (minutes <= 0) return '未设置';
    if (minutes % 60 == 0) {
      final h = minutes ~/ 60;
      return h == 1 ? '每 1 小时' : '每 $h 小时';
    }
    return '每 $minutes 分钟';
  }

  double? _estimateDailyRequests({
    required int weeksAhead,
    required int intervalMinutes,
  }) {
    if (intervalMinutes <= 0) return null;
    final perDayRuns = 1440 / intervalMinutes;
    return (1 + weeksAhead) * perDayRuns;
  }

  Future<bool> _confirmHighFrequencyIfNeeded({
    required BuildContext context,
    required int weeksAhead,
    required int intervalMinutes,
  }) async {
    final est = _estimateDailyRequests(
      weeksAhead: weeksAhead,
      intervalMinutes: intervalMinutes,
    );
    final risky = intervalMinutes < 15 || (est != null && est >= 200);
    if (!risky) return true;

    final detail = <String>[
      if (intervalMinutes < 15) '后台定时检查系统通常要求间隔不少于 15 分钟',
      if (est != null) '按当前设置，预计每天约 ${est.toStringAsFixed(0)} 次课表接口请求',
      '请求过于频繁可能导致耗电增加、流量增加，且可能触发学校系统的风控限制',
    ].join('\n');

    final proceed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('请求频率风险提示'),
              content: Text(detail),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('启用'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!proceed) return false;
    if (!context.mounted) return false;

    final disclaimer = <String>[
      detail,
      '',
      '请注意：',
      '1. 频繁请求可能导致耗电/流量增加，且可能触发学校系统风控（如账号被限制、请求被拒绝等）。',
      '2. 由此产生的任何直接或间接损失（包括但不限于账号限制、数据异常等）由用户自行承担。',
    ].join('\n');

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: Text('风险提醒'),
              content: Text(disclaimer),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: Text('返回修改'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('我已知悉'),
                ),
              ],
            );
          },
        ) ??
        false;
    return confirmed;
  }

  Future<bool> _confirmEnableScheduleUpdate(BuildContext context) async {
    final manufacturer = await AndroidBackgroundRestrictions.manufacturer();
    bool? ignoringBattery = await AndroidBackgroundRestrictions
        .isIgnoringBatteryOptimizations();
    bool? backgroundRestricted = await AndroidBackgroundRestrictions
        .isBackgroundRestricted();
    if (!context.mounted) return false;

    String batteryLabel() {
      if (ignoringBattery == null) return '未知';
      return ignoringBattery! ? '已忽略' : '未忽略';
    }

    String restrictedLabel() {
      if (backgroundRestricted == null) return '未知';
      return backgroundRestricted! ? '已限制' : '未限制';
    }

    final ok =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return StatefulBuilder(
              builder: (context, setDialogState) {
                Future<void> refresh() async {
                  final b = await AndroidBackgroundRestrictions
                      .isIgnoringBatteryOptimizations();
                  final r =
                      await AndroidBackgroundRestrictions.isBackgroundRestricted();
                  if (!context.mounted) return;
                  setDialogState(() {
                    ignoringBattery = b;
                    backgroundRestricted = r;
                  });
                }

                return AlertDialog(
                  title: Text('提示'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '请允许CQUT-Helper的自启动并忽略“电池优化”，否则可能无法正常唤醒课表定时检查。\n'
                          '若使用的是国产定制 UI，你还需要在系统设置中进行相应修改。',
                        ),
                        if (manufacturer != null) ...[
                          SizedBox(height: 8),
                          Text('设备：$manufacturer'),
                        ],
                        SizedBox(height: 12),
                        Text('电池优化：${batteryLabel()}'),
                        SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () async {
                                await AndroidBackgroundRestrictions
                                    .requestIgnoreBatteryOptimizations();
                                await refresh();
                              },
                              child: Text('去忽略电池优化'),
                            ),
                            OutlinedButton(
                              onPressed: () async {
                                await AndroidBackgroundRestrictions
                                    .openBatteryOptimizationSettings();
                                await refresh();
                              },
                              child: Text('电池优化设置'),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Text('后台限制：${restrictedLabel()}'),
                        SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: () async {
                                await AndroidBackgroundRestrictions
                                    .openAutoStartSettings();
                                await refresh();
                              },
                              child: Text('打开自启动设置'),
                            ),
                            OutlinedButton(
                              onPressed: () async {
                                await AndroidBackgroundRestrictions
                                    .openAppDetailsSettings();
                                await refresh();
                              },
                              child: Text('应用详情'),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text('自启动权限无法在所有设备上可靠自动检测，请在系统设置中确认已允许。'),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('继续启用'),
                    ),
                  ],
                );
              },
            );
          },
        ) ??
        false;

    return ok;
  }

  Future<int?> _askIntervalMinutes(BuildContext context, int initial) async {
    final controller = TextEditingController(text: initial.toString());
    final value = await showDialog<int?>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('设置检查间隔（分钟）'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(hintText: '例如 60（最小 15）'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final v = int.tryParse(controller.text.trim());
                Navigator.pop(context, v);
              },
              child: Text('确定'),
            ),
          ],
        );
      },
    );
    if (value == null) return null;
    if (value < 15) return 15;
    return value;
  }

  Future<bool> saveSettings() async {
    if (updateEnabled && intervalMinutes < 15) {
      intervalMinutes = 15;
    }
    if (updateEnabled) {
      final ok = await _confirmHighFrequencyIfNeeded(
        context: context,
        weeksAhead: weeksAhead,
        intervalMinutes: intervalMinutes,
      );
      if (!ok) return false;
    }

    if (updateEnabled && systemNotifyEnabled) {
      final ok = await LocalNotifications.ensurePermission();
      if (!ok) {
        systemNotifyEnabled = false;
        if (context.mounted) {
          await showDialog<void>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: Text('通知权限未授予'),
                content: Text('未授予通知权限，将无法发送系统通知提醒。你仍可使用应用内提示。'),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('知道了'),
                  ),
                ],
              );
            },
          );
        }
      }
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(ScheduleSettingsSheet.prefsKeyShowWeekend, showWeekend);
    await prefs.setInt(
      ScheduleSettingsSheet.prefsKeyUpdateWeeksAhead,
      weeksAhead,
    );
    await prefs.setBool(ScheduleSettingsSheet.prefsKeyUpdateEnabled, updateEnabled);
    await prefs.setInt(
      ScheduleSettingsSheet.prefsKeyUpdateIntervalMinutes,
      intervalMinutes,
    );
    await prefs.setBool(ScheduleSettingsSheet.prefsKeyUpdateShowDiff, showDiff);
    await prefs.setBool(
      ScheduleSettingsSheet.prefsKeyUpdateSystemNotifyEnabled,
      systemNotifyEnabled,
    );

    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: 'schedule_toggle_show_weekend',
        parameters: {'value': showWeekend},
      ),
    );

    widget.onSave(
      weeksAhead: weeksAhead,
      showWeekend: showWeekend,
      updateEnabled: updateEnabled,
      updateIntervalMinutes: intervalMinutes,
      updateShowDiff: showDiff,
      systemNotifyEnabled: systemNotifyEnabled,
    );

    await ScheduleUpdateWorker.syncFromPreferences();
    return true;
  }

  Future<void> maybeConfirmAndClose() async {
    if (confirmDialogOpen) return;
    if (!hasUnsavedChanges()) {
      if (context.mounted) Navigator.pop(context);
      return;
    }

    confirmDialogOpen = true;
    try {
      if (!context.mounted) return;
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

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) Navigator.pop(context);
      });
    } finally {
      confirmDialogOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final est = _estimateDailyRequests(
      weeksAhead: weeksAhead,
      intervalMinutes: intervalMinutes,
    );

    String weeksLabel() {
      if (weeksAhead == 0) return '仅本周';
      return '本周 + 未来 $weeksAhead 周';
    }

    final showRisk =
        updateEnabled && (intervalMinutes < 15 || (est != null && est >= 200));

    return PopScope(
      canPop: !hasUnsavedChanges(),
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
                  ListTile(
                    title: Text('课表更新检查范围'),
                    subtitle: Text(
                      widget.maxWeeksAhead == 0
                          ? '本学期周数不足'
                          : '${weeksLabel()}（上限：未来 ${widget.maxWeeksAhead} 周）',
                    ),
                  ),
                  if (widget.maxWeeksAhead > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Slider(
                        min: 0,
                        max: widget.maxWeeksAhead.toDouble(),
                        value: weeksAhead.toDouble(),
                        divisions: widget.maxWeeksAhead,
                        label: weeksLabel(),
                        onChanged: (v) {
                          setState(() {
                            weeksAhead = v.round();
                          });
                        },
                      ),
                    ),
                  SwitchListTile(
                    title: Text('启用定时检查'),
                    subtitle: Text('定期静默检查课表是否变化'),
                    value: updateEnabled,
                    onChanged: (value) async {
                      if (value && !updateEnabled) {
                        final ok = await _confirmEnableScheduleUpdate(context);
                        if (!ok) return;
                      }
                      setState(() {
                        updateEnabled = value;
                        if (updateEnabled && intervalMinutes < 15) {
                          intervalMinutes = 15;
                        }
                      });
                    },
                  ),
                  ListTile(
                    title: Text('检查间隔'),
                    subtitle: Text(
                      updateEnabled
                          ? _formatIntervalLabel(intervalMinutes)
                          : '未启用',
                    ),
                    enabled: updateEnabled,
                    onTap: !updateEnabled
                        ? null
                        : () async {
                            final v = await _askIntervalMinutes(
                              context,
                              intervalMinutes,
                            );
                            if (v == null) return;
                            setState(() {
                              intervalMinutes = v;
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
                    title: Text('系统通知提醒'),
                    subtitle: Text('在后台也发送系统通知提醒'),
                    value: systemNotifyEnabled,
                    onChanged: !updateEnabled
                        ? null
                        : (value) {
                            setState(() {
                              systemNotifyEnabled = value;
                            });
                          },
                  ),
                  if (showRisk)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Text(
                        est == null
                            ? '当前设置可能导致请求频繁'
                            : '当前设置预计每天约 ${est.toStringAsFixed(0)} 次请求，可能触发风控或增加耗电',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
                            onPressed: () async {
                              final ok = await saveSettings();
                              if (!ok) return;
                              if (!context.mounted) return;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              });
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

void showScheduleSettingsSheet(BuildContext context, {
  required int initialWeeksAhead,
  required bool initialShowWeekend,
  required bool initialUpdateEnabled,
  required int initialUpdateIntervalMinutes,
  required bool initialUpdateShowDiff,
  required bool initialSystemNotifyEnabled,
  required int maxWeeksAhead,
  required Function({
    required int weeksAhead,
    required bool showWeekend,
    required bool updateEnabled,
    required int updateIntervalMinutes,
    required bool updateShowDiff,
    required bool systemNotifyEnabled,
  }) onSave,
}) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return ScheduleSettingsSheet(
        initialWeeksAhead: initialWeeksAhead,
        initialShowWeekend: initialShowWeekend,
        initialUpdateEnabled: initialUpdateEnabled,
        initialUpdateIntervalMinutes: initialUpdateIntervalMinutes,
        initialUpdateShowDiff: initialUpdateShowDiff,
        initialSystemNotifyEnabled: initialSystemNotifyEnabled,
        maxWeeksAhead: maxWeeksAhead,
        onSave: onSave,
      );
    },
  );
}
