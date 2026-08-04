import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/hidden_courses_sheet.dart';
import 'package:flutter/material.dart';

import 'settings_schedule_scope.dart';

class ScheduleCoursesSettingsPage extends StatefulWidget {
  final SettingsScheduleScope scope;

  const ScheduleCoursesSettingsPage({super.key, required this.scope});

  @override
  State<ScheduleCoursesSettingsPage> createState() =>
      _ScheduleCoursesSettingsPageState();
}

class _ScheduleCoursesSettingsPageState
    extends State<ScheduleCoursesSettingsPage> {
  final ScheduleSettingsManager _manager = ScheduleSettingsManager();
  bool _loading = true;
  bool _showWeekend = false;
  bool _timeInfoEnabled = true;
  ScheduleDisplayDensity _density = ScheduleDisplayDensity.comfortable;
  int? _hiddenCourseCount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _manager.load();
    final hiddenCourses = widget.scope.canManageCourses
        ? await ScheduleCustomizationManager.instance.hiddenCourses(
            userId: widget.scope.userId,
            yearTerm: widget.scope.yearTerm,
          )
        : null;
    if (!mounted) return;
    setState(() {
      _showWeekend = _manager.showWeekend;
      _timeInfoEnabled = _manager.timeInfoEnabled;
      _density = _manager.displayDensity;
      _hiddenCourseCount = hiddenCourses?.length;
      _loading = false;
    });
  }

  Future<void> _saveSchedule({bool? showWeekend, bool? timeInfoEnabled}) async {
    setState(() {
      _showWeekend = showWeekend ?? _showWeekend;
      _timeInfoEnabled = timeInfoEnabled ?? _timeInfoEnabled;
    });
    await _manager.save(
      showWeekend: _showWeekend,
      timeInfoEnabled: _timeInfoEnabled,
      backgroundPollingEnabled: _manager.backgroundPollingEnabled,
      noticeApiBaseUrl: _manager.noticeApiBaseUrl,
    );
  }

  Future<void> _saveDensity(ScheduleDisplayDensity density) async {
    setState(() => _density = density);
    await _manager.saveExperienceSettings(
      remindersEnabled: _manager.remindersEnabled,
      defaultReminderMinutes: _manager.defaultReminderMinutes,
      displayDensity: density,
      defaultHomeTab: _manager.defaultHomeTab,
    );
  }

  Future<void> _openHiddenCourses() async {
    if (!widget.scope.canManageCourses) return;
    await showHiddenCoursesSheet(
      context,
      userId: widget.scope.userId,
      yearTerm: widget.scope.yearTerm,
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('课表与课程')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text('课表显示', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: Column(
                    children: [
                      SwitchListTile(
                        title: const Text('显示周末'),
                        subtitle: const Text('关闭后仅显示周一到周五'),
                        value: _showWeekend,
                        onChanged: (value) => _saveSchedule(showWeekend: value),
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        title: const Text('显示上课时间'),
                        subtitle: const Text('在课表左侧展示每节课的时间'),
                        value: _timeInfoEnabled,
                        onChanged: (value) =>
                            _saveSchedule(timeInfoEnabled: value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text('课表密度', style: Theme.of(context).textTheme.titleSmall),
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
                  onSelectionChanged: (value) => _saveDensity(value.first),
                ),
                const SizedBox(height: 20),
                Text('课程管理', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  child: ListTile(
                    leading: const Icon(Icons.visibility_off_outlined),
                    title: const Text('已隐藏课程'),
                    subtitle: Text(
                      !widget.scope.canManageCourses
                          ? '请先打开一次课表以确定当前学期'
                          : _hiddenCourseCount == 0
                          ? '${widget.scope.yearTerm} 学期 · 暂无隐藏课程'
                          : '${widget.scope.yearTerm} 学期 · $_hiddenCourseCount 门',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: widget.scope.canManageCourses
                        ? _openHiddenCourses
                        : null,
                  ),
                ),
              ],
            ),
    );
  }
}
