import 'package:cqut/manager/course_color_assignment_manager.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/theme/schedule_course_card_theme.dart';
import 'package:flutter/material.dart';

class SemesterCourseListPage extends StatefulWidget {
  final String yearTerm;
  final List<EventItem> events;

  const SemesterCourseListPage({
    super.key,
    required this.yearTerm,
    required this.events,
  });

  @override
  State<SemesterCourseListPage> createState() => _SemesterCourseListPageState();
}

class _SemesterCourseListPageState extends State<SemesterCourseListPage> {
  Map<String, int> _colorMap = <String, int>{};

  @override
  void initState() {
    super.initState();
    _colorMap = CourseColorAssignmentManager.instance.getCachedAssignments(
      widget.yearTerm,
    );
    _initColorMap();
  }

  String _buildCourseKey(EventItem event) {
    final eventId = event.eventID ?? '';
    final name = event.eventName ?? '';
    final address = event.address ?? '';
    final teacher = event.memberName ?? '';
    return '$eventId|$name|$address|$teacher';
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

  @override
  Widget build(BuildContext context) {
    final cardTheme =
        Theme.of(context).extension<ScheduleCourseCardTheme>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ScheduleCourseCardTheme.dark()
            : ScheduleCourseCardTheme.light());
    final courseMap = <String, EventItem>{};
    for (final event in widget.events) {
      final key = _buildCourseKey(event);
      courseMap.putIfAbsent(key, () => event);
    }
    final courseKeys = courseMap.keys.toList(growable: false)
      ..sort((a, b) {
        final aEvent = courseMap[a];
        final bEvent = courseMap[b];
        final aName = (aEvent?.eventName ?? '').trim();
        final bName = (bEvent?.eventName ?? '').trim();
        final byName = aName.compareTo(bName);
        if (byName != 0) return byName;
        final aTeacher = (aEvent?.memberName ?? '').trim();
        final bTeacher = (bEvent?.memberName ?? '').trim();
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
                final event = courseMap[key]!;
                final colorIndex = _colorIndex(
                  key,
                  cardTheme.backgrounds.length,
                );
                final backgroundColor = cardTheme.backgrounds[colorIndex];
                final borderColor = cardTheme.borders[colorIndex];
                final titleColor = cardTheme.titleColors[colorIndex];
                final descriptionColor =
                    cardTheme.descriptionColors[colorIndex];
                return Container(
                  decoration: BoxDecoration(
                    color: backgroundColor,
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
                      Text(
                        event.eventName ?? '未命名课程',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: titleColor,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '教师：${(event.memberName ?? '').trim().isEmpty ? '未知' : event.memberName}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: descriptionColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '教室：${(event.address ?? '').trim().isEmpty ? '未知' : event.address}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: descriptionColor,
                        ),
                      ),
                    ],
                  ),
                );
              },
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemCount: courseKeys.length,
            ),
    );
  }
}
