import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/course_detail_dialog.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/model/local_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/local_course_editor_page.dart';
import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:flutter/material.dart';

class SemesterCourseListPage extends StatefulWidget {
  final String yearTerm;
  final List<EventItem> events;
  final String userId;

  const SemesterCourseListPage({
    super.key,
    required this.yearTerm,
    required this.events,
    required this.userId,
  });

  @override
  State<SemesterCourseListPage> createState() => _SemesterCourseListPageState();
}

class _SemesterCourseListPageState extends State<SemesterCourseListPage> {
  Map<String, int> _colorMap = <String, int>{};
  Map<String, CoursePreference> _preferences = <String, CoursePreference>{};

  @override
  void initState() {
    super.initState();
    _colorMap = CourseColorAssignmentManager.instance.getCachedAssignments(
      widget.yearTerm,
    );
    _initColorMap();
    _loadPreferences();
  }

  String _buildCourseKey(EventItem event) {
    return CourseColorAssignmentManager.buildCourseNameKey(event.eventName);
  }

  String _customizationKey(EventItem event) =>
      (event.customizationKey ?? '').trim().isNotEmpty
      ? event.customizationKey!.trim()
      : ScheduleCustomizationManager.courseKeyForEvent(event);

  Future<void> _loadPreferences() async {
    if (widget.userId.trim().isEmpty) return;
    final preferences = await ScheduleCustomizationManager.instance
        .preferenceMap(userId: widget.userId, yearTerm: widget.yearTerm);
    if (!mounted) return;
    setState(() => _preferences = preferences);
  }

  Future<void> _editCoursePreference(List<EventItem> events) async {
    if (events.isEmpty || widget.userId.trim().isEmpty) return;
    final first = events.first;
    final key = _customizationKey(first);
    final preference = await showCoursePreferenceEditor(
      context,
      userId: widget.userId,
      yearTerm: widget.yearTerm,
      courseKey: key,
      currentName: (first.eventName ?? '').trim(),
      currentTeacher: (first.memberName ?? '').trim(),
      currentLocation: (first.address ?? '').trim(),
      initial: _preferences[key],
    );
    if (preference == null) return;
    await ScheduleCustomizationManager.instance.saveCoursePreference(
      preference,
    );
    if (!mounted) return;
    setState(() => _preferences[key] = preference);
  }

  Future<void> _initColorMap() async {
    final cardTheme =
        Theme.of(context).extension<ScheduleCourseCardTheme>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ScheduleCourseCardTheme.dark()
            : ScheduleCourseCardTheme.light());
    final keys = widget.events.map(_buildCourseKey).toSet();
    final assigned = await CourseColorAssignmentManager.instance
        .assignForCourses(
          term: widget.yearTerm,
          courseKeys: keys,
          paletteSize: cardTheme.backgrounds.length,
        );
    if (!mounted) return;
    setState(() {
      _colorMap = assigned;
    });
  }

  int _colorIndex(String key, int paletteSize) {
    if (paletteSize <= 0) return 0;
    return (_colorMap[key] ?? key.hashCode.abs()) % paletteSize;
  }

  String _safeValue(String? raw) {
    final v = (raw ?? '').trim();
    return v.isEmpty ? '未知' : v;
  }

  @override
  Widget build(BuildContext context) {
    final cardTheme =
        Theme.of(context).extension<ScheduleCourseCardTheme>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ScheduleCourseCardTheme.dark()
            : ScheduleCourseCardTheme.light());
    final courseMap = <String, List<EventItem>>{};
    for (final event in widget.events) {
      final preference = _preferences[_customizationKey(event)];
      if (preference?.hidden == true) continue;
      final key = _buildCourseKey(event);
      courseMap.putIfAbsent(key, () => <EventItem>[]).add(event);
    }
    final courseKeys = courseMap.keys.toList(growable: false)
      ..sort((a, b) {
        final aName = a.trim();
        final bName = b.trim();
        final byName = aName.compareTo(bName);
        if (byName != 0) return byName;
        final aList = courseMap[a] ?? const <EventItem>[];
        final bList = courseMap[b] ?? const <EventItem>[];
        final aTeacher = aList.isNotEmpty
            ? (aList.first.memberName ?? '').trim()
            : '';
        final bTeacher = bList.isNotEmpty
            ? (bList.first.memberName ?? '').trim()
            : '';
        return aTeacher.compareTo(bTeacher);
      });

    return Scaffold(
      appBar: AppBar(title: const Text('本学期课程'), centerTitle: true),
      body: courseKeys.isEmpty
          ? const Center(child: Text('暂无课程数据'))
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemBuilder: (context, index) {
                final key = courseKeys[index];
                final events = courseMap[key] ?? const <EventItem>[];
                final preference = events.isEmpty
                    ? null
                    : _preferences[_customizationKey(events.first)];
                final colorIndex =
                    preference?.colorIndex ??
                    _colorIndex(key, cardTheme.backgrounds.length);
                final backgroundColor = cardTheme.backgrounds[colorIndex];
                final borderColor = cardTheme.borders[colorIndex];
                final titleColor = cardTheme.titleColors[colorIndex];
                final descriptionColor =
                    cardTheme.descriptionColors[colorIndex];
                final preferredName = preference?.displayName?.trim() ?? '';
                final displayName = preferredName.isNotEmpty
                    ? preferredName
                    : (key.trim().isEmpty ? '未命名课程' : key.trim());
                final teacherSet =
                    events
                        .map((e) => _safeValue(e.memberName))
                        .toSet()
                        .toList(growable: false)
                      ..sort();
                final classroomSet =
                    events
                        .map((e) => _safeValue(e.address))
                        .toSet()
                        .toList(growable: false)
                      ..sort();
                return Material(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showCourseDetailDialog(
                      context,
                      courseName: displayName,
                      events: events,
                      closeButtonColor: cardTheme.buttonColors[colorIndex],
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderColor),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  displayName,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        color: titleColor,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                              ),
                              IconButton(
                                tooltip: '编辑课程个性化',
                                onPressed: () => _editCoursePreference(events),
                                icon: const Icon(Icons.tune, size: 20),
                                color: titleColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '教师：${teacherSet.join("、")}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: descriptionColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '教室：${classroomSet.join("、")}',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: descriptionColor),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '上课安排：${events.length}条',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: descriptionColor),
                          ),
                          if ((preference?.note ?? '').trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              '备注：${preference!.note.trim()}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: descriptionColor),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: courseKeys.length,
            ),
    );
  }
}
