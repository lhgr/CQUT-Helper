import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/widgets/app_select_field.dart';
import 'package:flutter/material.dart';

class CustomCourseEditorPage extends StatefulWidget {
  final String userId;
  final String encryptedPassword;
  final String yearTerm;
  final List<int> availableWeeks;
  final EventItem? initial;
  final ScheduleApi? api;

  const CustomCourseEditorPage({
    super.key,
    required this.userId,
    required this.encryptedPassword,
    required this.yearTerm,
    required this.availableWeeks,
    this.initial,
    this.api,
  });

  @override
  State<CustomCourseEditorPage> createState() => _CustomCourseEditorPageState();
}

class _CustomCourseEditorPageState extends State<CustomCourseEditorPage> {
  late final TextEditingController _title;
  late final TextEditingController _teacher;
  late final TextEditingController _location;
  late Set<int> _weeks;
  late int _weekDay;
  late int _startSession;
  late int _sessionCount;
  bool _saving = false;

  ScheduleApi get _api => widget.api ?? ScheduleApi();

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _title = TextEditingController(text: initial?.eventName ?? '');
    _teacher = TextEditingController(text: initial?.memberName ?? '');
    _location = TextEditingController(text: initial?.address ?? '');
    final initialWeeks = (initial?.weekList ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where(widget.availableWeeks.contains)
        .toSet();
    _weeks = initial == null || initialWeeks.isEmpty
        ? widget.availableWeeks.toSet()
        : initialWeeks;
    _weekDay = (int.tryParse(initial?.weekDay ?? '') ?? DateTime.now().weekday)
        .clamp(1, 7);
    _startSession = (int.tryParse(initial?.sessionStart ?? '') ?? 1).clamp(
      1,
      12,
    );
    _sessionCount = (int.tryParse(initial?.sessionLast ?? '') ?? 2).clamp(
      1,
      12,
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _teacher.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入课程或事件名称')));
      return;
    }
    if (_weeks.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少选择一个教学周')));
      return;
    }

    setState(() => _saving = true);
    final weeks = _weeks.toList()..sort();
    try {
      final eventId = (widget.initial?.eventID ?? '').trim();
      if (eventId.isEmpty) {
        await _api.addCustomEvent(
          userId: widget.userId,
          encryptedPassword: widget.encryptedPassword,
          yearTerm: widget.yearTerm,
          weekList: weeks,
          weekDay: _weekDay,
          sessionStart: _startSession,
          sessionCount: _sessionCount,
          eventName: title,
          address: _location.text.trim(),
          memberName: _teacher.text.trim(),
        );
      } else {
        await _api.editCustomEvent(
          userId: widget.userId,
          encryptedPassword: widget.encryptedPassword,
          eventId: eventId,
          weekList: weeks,
          weekDay: _weekDay,
          sessionStart: _startSession,
          sessionCount: _sessionCount,
          eventName: title,
          address: _location.text.trim(),
          memberName: _teacher.text.trim(),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('保存失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxCount = (13 - _startSession).clamp(1, 12);
    if (_sessionCount > maxCount) _sessionCount = maxCount;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.initial == null ? '添加自定义课程' : '编辑自定义课程'),
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
          const SizedBox(height: 18),
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
                    _weeks = widget.availableWeeks.toSet();
                  }
                });
              },
              child: Text(
                _weeks.length == widget.availableWeeks.length ? '取消全选' : '全选',
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: AppSelectField<int>(
                  value: _weekDay,
                  labelText: '星期',
                  sheetTitle: '选择星期',
                  options: List.generate(
                    7,
                    (index) => AppSelectOption(
                      value: index + 1,
                      label: '周${'一二三四五六日'[index]}',
                    ),
                  ),
                  onChanged: (value) => setState(() => _weekDay = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppSelectField<int>(
                  value: _startSession,
                  labelText: '开始节次',
                  sheetTitle: '选择开始节次',
                  options: List.generate(
                    12,
                    (index) => AppSelectOption(
                      value: index + 1,
                      label: '第${index + 1}节',
                    ),
                  ),
                  onChanged: (value) => setState(() => _startSession = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppSelectField<int>(
                  key: ValueKey((maxCount, _sessionCount)),
                  value: _sessionCount.clamp(1, maxCount),
                  labelText: '持续',
                  sheetTitle: '选择持续节数',
                  options: List.generate(
                    maxCount,
                    (index) => AppSelectOption(
                      value: index + 1,
                      label: '${index + 1}节',
                    ),
                  ),
                  onChanged: (value) => setState(() => _sessionCount = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('自定义课程将保存到学校课表服务，并在其他使用学校课表的设备上同步。'),
        ],
      ),
    );
  }
}
