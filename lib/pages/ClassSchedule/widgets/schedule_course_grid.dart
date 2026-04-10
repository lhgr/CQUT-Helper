import 'package:flutter/material.dart';
import 'package:cqut/manager/course_color_assignment_manager.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_course_card.dart';
import 'package:cqut/pages/ClassSchedule/widgets/course_detail_dialog.dart';

class ScheduleCourseGrid extends StatefulWidget {
  final List<EventItem> events;
  final String yearTerm;
  final double sessionHeight;
  final int sessionCount;
  final List<Color> backgroundColors;
  final List<Color> borderColors;
  final List<Color> titleColors;
  final List<Color> descriptionColors;
  final List<Color> buttonColors;
  final bool showWeekend;

  const ScheduleCourseGrid({
    super.key,
    required this.events,
    required this.yearTerm,
    this.sessionHeight = 60.0,
    this.sessionCount = 12,
    required this.backgroundColors,
    required this.borderColors,
    required this.titleColors,
    required this.descriptionColors,
    required this.buttonColors,
    this.showWeekend = true,
  });

  @override
  State<ScheduleCourseGrid> createState() => _ScheduleCourseGridState();
}

class _ScheduleCourseGridState extends State<ScheduleCourseGrid> {
  Map<String, int> _courseColorIndexMap = <String, int>{};

  @override
  void initState() {
    super.initState();
    _courseColorIndexMap = CourseColorAssignmentManager.instance
        .getCachedAssignments(widget.yearTerm);
    _warmupCourseColorMap();
  }

  @override
  void didUpdateWidget(covariant ScheduleCourseGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.yearTerm != widget.yearTerm) {
      _courseColorIndexMap = CourseColorAssignmentManager.instance
          .getCachedAssignments(widget.yearTerm);
    }
    if (oldWidget.yearTerm != widget.yearTerm ||
        oldWidget.events != widget.events ||
        oldWidget.backgroundColors.length != widget.backgroundColors.length ||
        oldWidget.showWeekend != widget.showWeekend) {
      _warmupCourseColorMap();
    }
  }

  String _buildCourseKey(EventItem event) {
    return CourseColorAssignmentManager.buildCourseNameKey(event.eventName);
  }

  int _safeIndex(int index) {
    if (widget.backgroundColors.isEmpty) {
      return 0;
    }
    return index % widget.backgroundColors.length;
  }

  int _fallbackIndexForKey(String key) {
    if (widget.backgroundColors.isEmpty) {
      return 0;
    }
    return key.hashCode.abs() % widget.backgroundColors.length;
  }

  Future<void> _warmupCourseColorMap() async {
    final paletteSize = widget.backgroundColors.length;
    if (paletteSize <= 0) return;
    final keys = widget.events.map(_buildCourseKey).toSet();
    final assigned = await CourseColorAssignmentManager.instance
        .assignForCourses(
          term: widget.yearTerm,
          courseKeys: keys,
          paletteSize: paletteSize,
        );
    if (!mounted) return;
    setState(() {
      _courseColorIndexMap = assigned;
    });
  }

  List<EventItem> _eventsWithSameCourseName(EventItem target) {
    final key = _buildCourseKey(target);
    return widget.events.where((event) => _buildCourseKey(event) == key).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int dayCount = widget.showWeekend ? 7 : 5;
        final double dayWidth = constraints.maxWidth / dayCount;
        final double totalHeight = widget.sessionHeight * widget.sessionCount;
        final visibleEvents = widget.showWeekend
            ? widget.events
            : widget.events
                  .where((event) {
                    final weekDay = int.tryParse(event.weekDay ?? '1') ?? 1;
                    return weekDay >= 1 && weekDay <= 5;
                  })
                  .toList(growable: false);

        return SizedBox(
          height: totalHeight,
          child: Stack(
            children: [
              // Grid lines
              ...List.generate(widget.sessionCount, (index) {
                return Positioned(
                  top: index * widget.sessionHeight,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: widget.sessionHeight,
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withAlpha(51),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              ...List.generate(dayCount, (index) {
                return Positioned(
                  left: index * dayWidth,
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: dayWidth,
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withAlpha(51),
                        ),
                      ),
                    ),
                  ),
                );
              }),

              // Events
              if (visibleEvents.isEmpty)
                Center(
                  child: Text(
                    "本周无课",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              else
                ...visibleEvents.map((event) {
                  final int weekDay = int.tryParse(event.weekDay ?? "1") ?? 1;
                  final int start =
                      int.tryParse(event.sessionStart ?? "1") ?? 1;
                  final int duration =
                      int.tryParse(event.sessionLast ?? "1") ?? 1;

                  // 将 weekDay 调整为从 0 开始的索引（假设 1=周一）
                  final int dayIndex = weekDay - 1;
                  if (dayIndex < 0 || dayIndex >= dayCount) {
                    return const SizedBox.shrink();
                  }

                  final key = _buildCourseKey(event);
                  final int colorIndex =
                      _courseColorIndexMap[key] ?? _fallbackIndexForKey(key);
                  final safeIndex = _safeIndex(colorIndex);
                  final Color backgroundColor =
                      widget.backgroundColors[safeIndex];
                  final Color borderColor = widget.borderColors[safeIndex];
                  final Color titleColor = widget.titleColors[safeIndex];
                  final Color descriptionColor =
                      widget.descriptionColors[safeIndex];

                  return Positioned(
                    left: dayIndex * dayWidth,
                    top: (start - 1) * widget.sessionHeight,
                    width: dayWidth,
                    height: duration * widget.sessionHeight,
                    child: ScheduleCourseCard(
                      event: event,
                      backgroundColor: backgroundColor,
                      borderColor: borderColor,
                      titleColor: titleColor,
                      descriptionColor: descriptionColor,
                      onTap: () {
                        showCourseDetailDialog(
                          context,
                          courseName: key,
                          events: _eventsWithSameCourseName(event),
                          closeButtonColor: widget.buttonColors[safeIndex],
                        );
                      },
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}
