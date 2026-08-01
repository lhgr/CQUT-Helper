import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/model/local_schedule_model.dart';
import 'package:flutter/material.dart';

class LocalCourseEditorPage extends StatefulWidget {
  final String userId;
  final String yearTerm;
  final List<int> availableWeeks;
  final LocalScheduleEvent? initial;

  const LocalCourseEditorPage({
    super.key,
    required this.userId,
    required this.yearTerm,
    required this.availableWeeks,
    this.initial,
  });

  @override
  State<LocalCourseEditorPage> createState() => _LocalCourseEditorPageState();
}

class _LocalCourseEditorPageState extends State<LocalCourseEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final TextEditingController _note;
  late Set<int> _weeks;
  late int _weekDay;
  late int _startSession;
  late int _sessionCount;
  late bool _specificDateMode;
  DateTime? _specificDate;
  int? _reminderMinutes;
  int? _colorIndex;
  bool _saving = false;

  static const _colors = <Color>[
    Colors.blue,
    Colors.deepOrange,
    Colors.teal,
    Colors.deepPurple,
    Colors.amber,
    Colors.red,
    Colors.pink,
    Colors.cyan,
    Colors.lime,
    Colors.purple,
    Colors.indigo,
  ];

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.title ?? '');
    _teacher = TextEditingController(text: initial?.teacher ?? '');
    _location = TextEditingController(text: initial?.location ?? '');
    _note = TextEditingController(text: initial?.note ?? '');
    _weeks = initial == null
        ? <int>{...widget.availableWeeks}
        : <int>{...initial.weeks};
    _weekDay = initial?.weekDay ?? DateTime.now().weekday;
    _startSession = initial?.startSession ?? 1;
    _sessionCount = initial?.sessionCount ?? 2;
    _specificDate = initial?.specificDate;
    _specificDateMode = _specificDate != null;
    _reminderMinutes = initial?.reminderMinutes;
    _colorIndex = initial?.colorIndex;
  }

  @override
  void dispose() {
    _title.dispose();
    _teacher.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _specificDate ?? DateTime.now(),
      firstDate: DateTime(DateTime.now().year - 1),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (date == null || !mounted) return;
    setState(() {
      _specificDate = date;
      _weekDay = date.weekday;
    });
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入课程或事件名称')));
      return;
    }
    if (_specificDateMode && _specificDate == null) {
      await _pickDate();
      if (_specificDate == null) return;
      if (!mounted) return;
    }
    if (!_specificDateMode && _weeks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个教学周')));
      return;
    }
    setState(() => _saving = true);
    final now = DateTime.now();
    final initial = widget.initial;
    final event = LocalScheduleEvent(
      id: initial?.id ?? ScheduleCustomizationManager.instance.newId(),
      userId: widget.userId,
      yearTerm: widget.yearTerm,
      title: title,
      teacher: _teacher.text.trim(),
      location: _location.text.trim(),
      note: _note.text.trim(),
      weeks: _specificDateMode ? const <int>[] : (_weeks.toList()..sort()),
      weekDay: _weekDay,
      startSession: _startSession,
      sessionCount: _sessionCount,
      specificDate: _specificDateMode ? _specificDate : null,
      reminderMinutes: _reminderMinutes,
      colorIndex: _colorIndex,
      source: initial?.source ?? LocalScheduleSource.manual,
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
    );
    await ScheduleCustomizationManager.instance.saveLocalEvent(event);
    if (!mounted) return;
    Navigator.of(context).pop(event);
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = (13 - _startSession).clamp(1, 12);
    if (_sessionCount > maxCount) _sessionCount = maxCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '添加课程或事件' : '编辑课程或事件'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '保存中' : '保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          TextField(
            controller: _title,
            autofocus: widget.initial == null,
            decoration: const InputDecoration(
              labelText: '名称',
              prefixIcon: Icon(Icons.book_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _teacher,
            decoration: const InputDecoration(
              labelText: '教师（可选）',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _location,
            decoration: const InputDecoration(
              labelText: '地点（可选）',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: '备注（可选）',
              prefixIcon: Icon(Icons.notes),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 18),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('按教学周')),
              ButtonSegment(value: true, label: Text('指定日期')),
            ],
            selected: {_specificDateMode},
            onSelectionChanged: (value) {
              setState(() => _specificDateMode = value.first);
            },
          ),
          const SizedBox(height: 16),
          if (_specificDateMode)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('日期'),
              subtitle: Text(
                _specificDate == null
                    ? '尚未选择'
                    : '${_specificDate!.year}-${_specificDate!.month.toString().padLeft(2, '0')}-${_specificDate!.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _pickDate,
            )
          else ...[
            Text('教学周', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: widget.availableWeeks
                  .map(
                    (week) => FilterChip(
                      label: Text('$week'),
                      selected: _weeks.contains(week),
                      onSelected: (selected) {
                        setState(() {
                          selected ? _weeks.add(week) : _weeks.remove(week);
                        });
                      },
                    ),
                  )
                  .toList(),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () {
                  setState(() {
                    if (_weeks.length == widget.availableWeeks.length) {
                      _weeks.clear();
                    } else {
                      _weeks = <int>{...widget.availableWeeks};
                    }
                  });
                },
                child: Text(
                  _weeks.length == widget.availableWeeks.length ? '取消全选' : '全选',
                ),
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _weekDay,
                  decoration: const InputDecoration(labelText: '星期'),
                  items: List.generate(
                    7,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('周${'一二三四五六日'[index]}'),
                    ),
                  ),
                  onChanged: _specificDateMode
                      ? null
                      : (value) => setState(() => _weekDay = value ?? 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  initialValue: _startSession,
                  decoration: const InputDecoration(labelText: '开始节次'),
                  items: List.generate(
                    12,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('第${index + 1}节'),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _startSession = value ?? 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey(maxCount),
                  initialValue: _sessionCount.clamp(1, maxCount),
                  decoration: const InputDecoration(labelText: '持续'),
                  items: List.generate(
                    maxCount,
                    (index) => DropdownMenuItem(
                      value: index + 1,
                      child: Text('${index + 1}节'),
                    ),
                  ),
                  onChanged: (value) =>
                      setState(() => _sessionCount = value ?? 1),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int?>(
            initialValue: _reminderMinutes,
            decoration: const InputDecoration(
              labelText: '课前提醒',
              prefixIcon: Icon(Icons.notifications_outlined),
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('跟随全局设置')),
              DropdownMenuItem(value: 0, child: Text('不提醒')),
              DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
              DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
              DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
              DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
            ],
            onChanged: (value) => setState(() => _reminderMinutes = value),
          ),
          const SizedBox(height: 18),
          Text('课程颜色', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: List.generate(_colors.length, (index) {
              final selected = _colorIndex == index;
              return Semantics(
                selected: selected,
                label: '颜色 ${index + 1}',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => setState(() => _colorIndex = index),
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _colors[index],
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

Future<CoursePreference?> showCoursePreferenceEditor(
  BuildContext context, {
  required String userId,
  required String yearTerm,
  required String courseKey,
  required String currentName,
  required String currentTeacher,
  required String currentLocation,
  required CoursePreference? initial,
}) async {
  return showModalBottomSheet<CoursePreference>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CoursePreferenceEditorSheet(
      userId: userId,
      yearTerm: yearTerm,
      courseKey: courseKey,
      currentName: currentName,
      currentTeacher: currentTeacher,
      currentLocation: currentLocation,
      initial: initial,
    ),
  );
}

class _CoursePreferenceEditorSheet extends StatefulWidget {
  final String userId;
  final String yearTerm;
  final String courseKey;
  final String currentName;
  final String currentTeacher;
  final String currentLocation;
  final CoursePreference? initial;

  const _CoursePreferenceEditorSheet({
    required this.userId,
    required this.yearTerm,
    required this.courseKey,
    required this.currentName,
    required this.currentTeacher,
    required this.currentLocation,
    required this.initial,
  });

  @override
  State<_CoursePreferenceEditorSheet> createState() =>
      _CoursePreferenceEditorSheetState();
}

class _CoursePreferenceEditorSheetState
    extends State<_CoursePreferenceEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late final TextEditingController _note;
  late bool _hidden;
  int? _reminder;
  int? _color;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _name = TextEditingController(
      text: initial?.displayName ?? widget.currentName,
    );
    _teacher = TextEditingController(
      text: initial?.teacher ?? widget.currentTeacher,
    );
    _location = TextEditingController(
      text: initial?.location ?? widget.currentLocation,
    );
    _note = TextEditingController(text: initial?.note ?? '');
    _hidden = initial?.hidden ?? false;
    _reminder = initial?.reminderMinutes;
    _color = initial?.colorIndex;
  }

  @override
  void dispose() {
    _name.dispose();
    _teacher.dispose();
    _location.dispose();
    _note.dispose();
    super.dispose();
  }

  String? _overrideValue(String value, String original) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized == original.trim()) return null;
    return normalized;
  }

  String? _normalizedInitialValue(String? value, String original) {
    return _overrideValue(value ?? '', original);
  }

  bool _hasEffectiveChanges(CoursePreference value) {
    final initial = widget.initial;
    return value.displayName !=
            _normalizedInitialValue(initial?.displayName, widget.currentName) ||
        value.teacher !=
            _normalizedInitialValue(initial?.teacher, widget.currentTeacher) ||
        value.location !=
            _normalizedInitialValue(
              initial?.location,
              widget.currentLocation,
            ) ||
        value.note != (initial?.note ?? '').trim() ||
        value.hidden != (initial?.hidden ?? false) ||
        value.reminderMinutes != initial?.reminderMinutes ||
        value.colorIndex != initial?.colorIndex;
  }

  void _save() {
    final value = CoursePreference(
      userId: widget.userId,
      yearTerm: widget.yearTerm,
      courseKey: widget.courseKey,
      displayName: _overrideValue(_name.text, widget.currentName),
      teacher: _overrideValue(_teacher.text, widget.currentTeacher),
      location: _overrideValue(_location.text, widget.currentLocation),
      note: _note.text.trim(),
      hidden: _hidden,
      reminderMinutes: _reminder,
      colorIndex: _color,
      updatedAt: DateTime.now(),
    );
    Navigator.of(context).pop(_hasEffectiveChanges(value) ? value : null);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          16,
          0,
          16,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('课程个性化', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: '显示名称'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _teacher,
              decoration: const InputDecoration(labelText: '教师'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _location,
              decoration: const InputDecoration(labelText: '地点'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '备注'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('隐藏该课程'),
              subtitle: const Text('保留教务数据，但不在课表中展示'),
              value: _hidden,
              onChanged: (value) => setState(() => _hidden = value),
            ),
            DropdownButtonFormField<int?>(
              initialValue: _reminder,
              decoration: const InputDecoration(labelText: '课前提醒'),
              items: const [
                DropdownMenuItem(value: null, child: Text('跟随全局设置')),
                DropdownMenuItem(value: 0, child: Text('不提醒')),
                DropdownMenuItem(value: 5, child: Text('提前 5 分钟')),
                DropdownMenuItem(value: 10, child: Text('提前 10 分钟')),
                DropdownMenuItem(value: 15, child: Text('提前 15 分钟')),
                DropdownMenuItem(value: 30, child: Text('提前 30 分钟')),
              ],
              onChanged: (value) => setState(() => _reminder = value),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                children: List.generate(11, (index) {
                  return ChoiceChip(
                    label: Text('${index + 1}'),
                    selected: _color == index,
                    onSelected: (_) => setState(() => _color = index),
                  );
                }),
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(onPressed: _save, child: const Text('保存')),
            ),
          ],
        ),
      ),
    );
  }
}
