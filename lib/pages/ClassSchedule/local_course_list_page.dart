import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/model/local_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/local_course_editor_page.dart';
import 'package:flutter/material.dart';

class LocalCourseListPage extends StatefulWidget {
  final String userId;
  final String yearTerm;
  final List<int> availableWeeks;

  const LocalCourseListPage({
    super.key,
    required this.userId,
    required this.yearTerm,
    required this.availableWeeks,
  });

  @override
  State<LocalCourseListPage> createState() => _LocalCourseListPageState();
}

class _LocalCourseListPageState extends State<LocalCourseListPage> {
  late Future<
    ({
      List<LocalScheduleEvent> events,
      Map<String, CoursePreference> preferences,
    })
  >
  _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    _future = () async {
      final manager = ScheduleCustomizationManager.instance;
      final events = await manager.listLocalEvents(
        userId: widget.userId,
        yearTerm: widget.yearTerm,
      );
      final preferences = await manager.preferenceMap(
        userId: widget.userId,
        yearTerm: widget.yearTerm,
      );
      return (events: events, preferences: preferences);
    }();
  }

  Future<void> _openEditor([LocalScheduleEvent? event]) async {
    final changed = await Navigator.of(context).push<LocalScheduleEvent>(
      MaterialPageRoute(
        builder: (_) => LocalCourseEditorPage(
          userId: widget.userId,
          yearTerm: widget.yearTerm,
          availableWeeks: widget.availableWeeks,
          initial: event,
        ),
      ),
    );
    if (changed != null && mounted) setState(_reload);
  }

  Future<void> _delete(LocalScheduleEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除本地课程'),
        content: Text('确定删除“${event.title}”吗？此操作不会修改教务系统。'),
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
    await ScheduleCustomizationManager.instance.deleteLocalEvent(event);
    if (mounted) setState(_reload);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('本地课程与事件')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditor,
        icon: const Icon(Icons.add),
        label: const Text('添加'),
      ),
      body:
          FutureBuilder<
            ({
              List<LocalScheduleEvent> events,
              Map<String, CoursePreference> preferences,
            })
          >(
            future: _future,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final events =
                  snapshot.data?.events ?? const <LocalScheduleEvent>[];
              final hidden =
                  (snapshot.data?.preferences.values ??
                          const <CoursePreference>[])
                      .where((preference) => preference.hidden)
                      .toList(growable: false);
              if (events.isEmpty && hidden.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('暂无本地课程。可添加重复课程、临时事件，或从 ICS 文件导入。'),
                  ),
                );
              }
              final itemCount =
                  events.length + (hidden.isEmpty ? 0 : hidden.length + 1);
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                itemCount: itemCount,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  if (hidden.isNotEmpty && index == 0) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
                      child: Text(
                        '已隐藏的教务课程',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    );
                  }
                  if (hidden.isNotEmpty && index <= hidden.length) {
                    final preference = hidden[index - 1];
                    final title = (preference.displayName ?? '').trim().isEmpty
                        ? preference.courseKey.replaceFirst(
                            RegExp(r'^(id:|course:)'),
                            '',
                          )
                        : preference.displayName!.trim();
                    return Card(
                      elevation: 0,
                      child: ListTile(
                        leading: const Icon(Icons.visibility_off_outlined),
                        title: Text(title),
                        subtitle: const Text('已从课表和桌面小组件中隐藏'),
                        trailing: TextButton(
                          onPressed: () async {
                            final restored = CoursePreference(
                              userId: preference.userId,
                              yearTerm: preference.yearTerm,
                              courseKey: preference.courseKey,
                              displayName: preference.displayName,
                              teacher: preference.teacher,
                              location: preference.location,
                              note: preference.note,
                              hidden: false,
                              reminderMinutes: preference.reminderMinutes,
                              colorIndex: preference.colorIndex,
                              updatedAt: DateTime.now(),
                            );
                            await ScheduleCustomizationManager.instance
                                .saveCoursePreference(restored);
                            if (mounted) setState(_reload);
                          },
                          child: const Text('恢复显示'),
                        ),
                      ),
                    );
                  }
                  final eventIndex =
                      index - (hidden.isEmpty ? 0 : hidden.length + 1);
                  final event = events[eventIndex];
                  final dateText = event.specificDate == null
                      ? '周${'一二三四五六日'[event.weekDay - 1]} · '
                            '第${event.startSession}-${event.startSession + event.sessionCount - 1}节 · '
                            '${event.weeks.length}个教学周'
                      : '${localScheduleDateKey(event.specificDate!)} · '
                            '第${event.startSession}-${event.startSession + event.sessionCount - 1}节';
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      leading: Icon(
                        event.source == LocalScheduleSource.ics
                            ? Icons.event_available_outlined
                            : Icons.edit_calendar_outlined,
                      ),
                      title: Text(event.title),
                      subtitle: Text(
                        [
                          dateText,
                          if (event.location.isNotEmpty) event.location,
                          if (event.note.isNotEmpty) event.note,
                        ].join('\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _openEditor(event),
                      trailing: PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _openEditor(event);
                          if (value == 'delete') _delete(event);
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
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
