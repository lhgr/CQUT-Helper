import 'package:cqut_helper/model/course_preference_model.dart';
import 'package:flutter/material.dart';

Future<CoursePreference?> showCoursePreferenceEditor(
  BuildContext context, {
  required String userId,
  required String yearTerm,
  required String courseKey,
  required String currentName,
  required String currentTeacher,
  required String currentLocation,
  required CoursePreference? initial,
}) {
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
              subtitle: const Text('保留学校数据，但不在课表中展示'),
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
                children: List.generate(
                  11,
                  (index) => ChoiceChip(
                    label: Text('${index + 1}'),
                    selected: _color == index,
                    onSelected: (_) => setState(() => _color = index),
                  ),
                ),
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
