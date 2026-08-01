import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/custom_course_editor_page.dart';
import 'package:flutter/material.dart';

class CustomCourseListPage extends StatefulWidget {
  final String userId;
  final String encryptedPassword;
  final String yearTerm;
  final List<int> availableWeeks;
  final ScheduleApi? api;
  final VoidCallback? onChanged;

  const CustomCourseListPage({
    super.key,
    required this.userId,
    required this.encryptedPassword,
    required this.yearTerm,
    required this.availableWeeks,
    this.api,
    this.onChanged,
  });

  @override
  State<CustomCourseListPage> createState() => _CustomCourseListPageState();
}

class _CustomCourseListPageState extends State<CustomCourseListPage> {
  late Future<List<EventItem>> _future;
  int _completed = 0;
  int _total = 0;

  ScheduleApi get _api => widget.api ?? ScheduleApi();

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _completed = 0;
    _total = widget.availableWeeks.length;
    _future = _api.fetchCustomEvents(
      userId: widget.userId,
      encryptedPassword: widget.encryptedPassword,
      yearTerm: widget.yearTerm,
      weeks: widget.availableWeeks,
      onProgress: (completed, total) {
        if (!mounted) return;
        setState(() {
          _completed = completed;
          _total = total;
        });
      },
    );
  }

  Future<void> _openEditor([EventItem? event]) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomCourseEditorPage(
          userId: widget.userId,
          encryptedPassword: widget.encryptedPassword,
          yearTerm: widget.yearTerm,
          availableWeeks: widget.availableWeeks,
          initial: event,
          api: _api,
        ),
      ),
    );
    if (changed == true && mounted) {
      widget.onChanged?.call();
      setState(_reload);
    }
  }

  Future<void> _delete(EventItem event) async {
    final title = (event.eventName ?? '').trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除自定义课程'),
        content: Text('确定从学校课表中删除“$title”吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final eventId = (event.eventID ?? '').trim();
    try {
      await _api.deleteCustomEvent(
        userId: widget.userId,
        encryptedPassword: widget.encryptedPassword,
        eventId: eventId,
      );
      if (!mounted) return;
      widget.onChanged?.call();
      setState(_reload);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('删除失败：$error'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _weekText(EventItem event) {
    final weeks =
        (event.weekList ?? const <String>[])
            .map(int.tryParse)
            .whereType<int>()
            .toList()
          ..sort();
    return weeks.isEmpty ? '未设置教学周' : '第 ${weeks.join('、')} 周';
  }

  String _timeText(EventItem event) {
    const weekdays = '一二三四五六日';
    final day = (int.tryParse(event.weekDay ?? '') ?? 1).clamp(1, 7);
    final start = int.tryParse(event.sessionStart ?? '') ?? 1;
    final count = int.tryParse(event.sessionLast ?? '') ?? 1;
    final end = start + count - 1;
    return '周${weekdays[day - 1]} · 第 $start–$end 节';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('自定义课程')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add),
        label: const Text('添加'),
      ),
      body: FutureBuilder<List<EventItem>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            final progress = _total == 0 ? null : _completed / _total;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    Text(
                      _total == 0
                          ? '正在读取学校课表…'
                          : '正在读取学校课表（$_completed/$_total 周）',
                    ),
                  ],
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('读取自定义课程失败：${snapshot.error}'),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => setState(_reload),
                      child: const Text('重试'),
                    ),
                  ],
                ),
              ),
            );
          }
          final events = snapshot.data ?? const <EventItem>[];
          if (events.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('学校课表中暂无自定义课程。'),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: events.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final event = events[index];
              final teacher = (event.memberName ?? '').trim();
              final location = (event.address ?? '').trim();
              return Card(
                elevation: 0,
                child: ListTile(
                  leading: const Icon(Icons.edit_calendar_outlined),
                  title: Text((event.eventName ?? '').trim()),
                  subtitle: Text(
                    [
                      _weekText(event),
                      _timeText(event),
                      if (teacher.isNotEmpty) teacher,
                      if (location.isNotEmpty) location,
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  onTap: () => _openEditor(event),
                  trailing: IconButton(
                    tooltip: '删除',
                    onPressed: () => _delete(event),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
