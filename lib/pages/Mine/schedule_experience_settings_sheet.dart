import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> showScheduleExperienceSettingsSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const ScheduleExperienceSettingsSheet(),
  );
}

class ScheduleExperienceSettingsSheet extends StatefulWidget {
  const ScheduleExperienceSettingsSheet({super.key});

  @override
  State<ScheduleExperienceSettingsSheet> createState() =>
      _ScheduleExperienceSettingsSheetState();
}

class _ScheduleExperienceSettingsSheetState
    extends State<ScheduleExperienceSettingsSheet> {
  final ScheduleSettingsManager _manager = ScheduleSettingsManager();
  bool _loading = true;
  bool _saving = false;
  bool _remindersEnabled = false;
  bool _exactAlarmGranted = false;
  int _defaultMinutes = 10;
  ScheduleDisplayDensity _density = ScheduleDisplayDensity.comfortable;
  int _defaultHomeTab = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _manager.load();
    final exactAlarmGranted = _manager.remindersEnabled
        ? await LocalNotifications.canScheduleExactNotifications()
        : false;
    if (!mounted) return;
    setState(() {
      _remindersEnabled = _manager.remindersEnabled;
      _exactAlarmGranted = exactAlarmGranted;
      _defaultMinutes = _manager.defaultReminderMinutes;
      _density = _manager.displayDensity;
      _defaultHomeTab = _manager.defaultHomeTab;
      _loading = false;
    });
  }

  Future<void> _toggleReminders(bool value) async {
    if (value) {
      final granted =
          await LocalNotifications.ensureCourseReminderPermissions();
      if (!granted) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('需要通知和“闹钟与提醒”权限才能启用课前提醒')));
        return;
      }
    }
    if (mounted) {
      setState(() {
        _remindersEnabled = value;
        _exactAlarmGranted = value;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    if (_remindersEnabled &&
        !await LocalNotifications.ensureCourseReminderPermissions()) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _exactAlarmGranted = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先允许通知和“闹钟与提醒”权限')));
      return;
    }
    await _manager.saveExperienceSettings(
      remindersEnabled: _remindersEnabled,
      defaultReminderMinutes: _defaultMinutes,
      displayDensity: _density,
      defaultHomeTab: _defaultHomeTab,
    );
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    if (_remindersEnabled && userId.isNotEmpty) {
      await CourseReminderScheduler.rescheduleForUser(userId);
    } else {
      await CourseReminderScheduler.cancelAll();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SafeArea(
        child: SizedBox(
          height: 240,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('课程与体验', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('课前提醒'),
              subtitle: const Text('课程同步或编辑后自动重建未来 60 天提醒'),
              value: _remindersEnabled,
              onChanged: _toggleReminders,
            ),
            if (_remindersEnabled)
              DropdownButtonFormField<int>(
                initialValue: _defaultMinutes,
                decoration: const InputDecoration(labelText: '默认提前时间'),
                items: const [
                  DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                  DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
                  DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                  DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
                ],
                onChanged: (value) =>
                    setState(() => _defaultMinutes = value ?? 10),
              ),
            if (_remindersEnabled && !_exactAlarmGranted)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('尚未获得精确闹钟权限，课程提醒不会生效')),
                  ],
                ),
              ),
            const SizedBox(height: 18),
            Text('课表显示密度', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<ScheduleDisplayDensity>(
              segments: const [
                ButtonSegment(
                  value: ScheduleDisplayDensity.compact,
                  label: Text('紧凑'),
                ),
                ButtonSegment(
                  value: ScheduleDisplayDensity.comfortable,
                  label: Text('标准'),
                ),
                ButtonSegment(
                  value: ScheduleDisplayDensity.spacious,
                  label: Text('宽松'),
                ),
              ],
              selected: {_density},
              onSelectionChanged: (value) =>
                  setState(() => _density = value.first),
            ),
            const SizedBox(height: 18),
            DropdownButtonFormField<int>(
              initialValue: _defaultHomeTab,
              decoration: const InputDecoration(labelText: '启动后默认页面'),
              items: const [
                DropdownMenuItem(value: 0, child: Text('今日')),
                DropdownMenuItem(value: 1, child: Text('课表')),
                DropdownMenuItem(value: 2, child: Text('我的')),
              ],
              onChanged: (value) =>
                  setState(() => _defaultHomeTab = value ?? 1),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '保存中…' : '保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
