import 'package:flutter/material.dart';
import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_card.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/course_detail_dialog.dart';

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
    return widget.events
        .where((event) => _buildCourseKey(event) == key)
        .toList(growable: false);
  }

  int _safeParsePositiveInt(String? raw, {int fallback = 1}) {
    final value = int.tryParse((raw ?? '').trim());
    if (value == null || value <= 0) return fallback;
    return value;
  }

  _EventRange _eventRange(EventItem event) {
    final start = _safeParsePositiveInt(event.sessionStart, fallback: 1);
    var duration = _safeParsePositiveInt(event.sessionLast, fallback: 1);

    if (duration <= 0) duration = 1;
    var end = start + duration - 1;
    if (end < start) end = start;
    return _EventRange(start: start, end: end);
  }

  List<_ConflictGroup> _buildConflictGroups(List<EventItem> events) {
    final byDay = <int, List<_EventWithRange>>{};
    for (final event in events) {
      final weekDay = _safeParsePositiveInt(event.weekDay, fallback: 1);
      final range = _eventRange(event);
      byDay
          .putIfAbsent(weekDay, () => <_EventWithRange>[])
          .add(_EventWithRange(event: event, range: range));
    }

    final groups = <_ConflictGroup>[];
    for (final entry in byDay.entries) {
      final dayEvents = entry.value;
      dayEvents.sort((a, b) {
        final byStart = a.range.start.compareTo(b.range.start);
        if (byStart != 0) return byStart;
        final byEnd = a.range.end.compareTo(b.range.end);
        if (byEnd != 0) return byEnd;
        return _buildCourseKey(a.event).compareTo(_buildCourseKey(b.event));
      });
      if (dayEvents.isEmpty) continue;

      var currentEvents = <_EventWithRange>[dayEvents.first];
      var currentEnd = dayEvents.first.range.end;

      void flushCurrent() {
        if (currentEvents.isEmpty) return;
        groups.add(
          _ConflictGroup(
            weekDay: entry.key,
            events: currentEvents.map((e) => e.event).toList(growable: false),
          ),
        );
      }

      for (int i = 1; i < dayEvents.length; i++) {
        final item = dayEvents[i];
        if (item.range.start <= currentEnd) {
          currentEvents.add(item);
          if (item.range.end > currentEnd) currentEnd = item.range.end;
          continue;
        }
        flushCurrent();
        currentEvents = <_EventWithRange>[item];
        currentEnd = item.range.end;
      }
      flushCurrent();
    }
    return groups;
  }

  _EventRange _groupRange(_ConflictGroup group) {
    var minStart = 999;
    var maxEnd = 0;
    for (final event in group.events) {
      final range = _eventRange(event);
      if (range.start < minStart) minStart = range.start;
      if (range.end > maxEnd) maxEnd = range.end;
    }
    if (minStart == 999) minStart = 1;
    if (maxEnd <= 0) maxEnd = minStart;
    return _EventRange(start: minStart, end: maxEnd);
  }

  int _durationPriority(_EventWithRange item) {
    if (item.range.duration == 2) {
      // 优先标准连排双节：1-2、3-4、5-6...
      return item.range.start.isOdd ? 0 : 1;
    }
    return 2;
  }

  bool _isOverlapped(_EventRange a, _EventRange b) {
    return a.start <= b.end && b.start <= a.end;
  }

  bool _containsStart(_EventRange container, int sessionStart) {
    return container.start <= sessionStart && sessionStart <= container.end;
  }

  bool _sameEvent(EventItem a, EventItem b) {
    final aId = (a.eventID ?? '').trim();
    final bId = (b.eventID ?? '').trim();
    if (aId.isNotEmpty && bId.isNotEmpty) return aId == bId;
    final ak = _buildCourseKey(a);
    final bk = _buildCourseKey(b);
    if (ak != bk) return false;
    final ar = _eventRange(a);
    final br = _eventRange(b);
    return ar.start == br.start &&
        ar.end == br.end &&
        (a.weekDay ?? '').trim() == (b.weekDay ?? '').trim() &&
        (a.address ?? '').trim() == (b.address ?? '').trim() &&
        (a.memberName ?? '').trim() == (b.memberName ?? '').trim();
  }

  _ConflictRenderPlan _buildRenderPlan(List<_ConflictGroup> groups) {
    final cards = <_DisplayCard>[];
    final borders = <_BorderOverlay>[];

    for (final group in groups) {
      final withRanges = group.events
          .map((e) => _EventWithRange(event: e, range: _eventRange(e)))
          .toList(growable: false);

      if (withRanges.length <= 1) {
        if (withRanges.isEmpty) continue;
        final only = withRanges.first;
        cards.add(
          _DisplayCard(
            weekDay: group.weekDay,
            start: only.range.start,
            end: only.range.end,
            event: only.event,
            conflictCount: 0,
            visualInset: 0,
            group: group,
          ),
        );
        continue;
      }

      final sorted = List<_EventWithRange>.from(withRanges);
      sorted.sort((a, b) {
        final pa = _durationPriority(a);
        final pb = _durationPriority(b);
        if (pa != pb) return pa.compareTo(pb);
        final byDuration = a.range.duration.compareTo(b.range.duration);
        if (byDuration != 0) return byDuration;
        final byStart = a.range.start.compareTo(b.range.start);
        if (byStart != 0) return byStart;
        return _buildCourseKey(a.event).compareTo(_buildCourseKey(b.event));
      });

      final selected = <_EventWithRange>[];
      for (final item in sorted) {
        final hasOverlap = selected.any(
          (picked) => _isOverlapped(picked.range, item.range),
        );
        if (!hasOverlap) {
          selected.add(item);
        }
      }
      if (selected.isEmpty) {
        selected.add(sorted.first);
      }

      final hidden = sorted
          .where(
            (candidate) => !selected.any(
              (picked) => _sameEvent(picked.event, candidate.event),
            ),
          )
          .toList(growable: false);
      final hiddenOrder = <String, int>{};
      for (int i = 0; i < hidden.length; i++) {
        final event = hidden[i].event;
        final eventId = (event.eventID ?? '').trim();
        final range = hidden[i].range;
        final fallbackKey =
            '${_buildCourseKey(event)}|${group.weekDay}|${range.start}|${range.end}|${event.memberName ?? ''}|${event.address ?? ''}';
        hiddenOrder[eventId.isNotEmpty ? 'id:$eventId' : 'k:$fallbackKey'] = i;
      }

      for (final picked in selected) {
        var count = 0;
        for (final h in hidden) {
          if (_isOverlapped(h.range, picked.range)) {
            count++;
          }
        }
        final overlapHiddenCount = hidden
            .where((h) => _isOverlapped(h.range, picked.range))
            .length;
        final visualInset = overlapHiddenCount <= 0
            ? 0.0
            : (2.0 + (overlapHiddenCount - 1) * 1.5).clamp(0.0, 8.0);
        cards.add(
          _DisplayCard(
            weekDay: group.weekDay,
            start: picked.range.start,
            end: picked.range.end,
            event: picked.event,
            conflictCount: count,
            visualInset: visualInset,
            group: group,
          ),
        );
      }

      int borderInsetLevelFor(_EventWithRange target) {
        var level = 0;
        for (final other in hidden) {
          if (identical(other, target)) continue;
          final contains =
              other.range.start <= target.range.start &&
              other.range.end >= target.range.end;
          if (contains && other.range.duration > target.range.duration) {
            level++;
          }
        }
        return level;
      }

      for (final h in hidden) {
        final eventId = (h.event.eventID ?? '').trim();
        final fallbackKey =
            '${_buildCourseKey(h.event)}|${group.weekDay}|${h.range.start}|${h.range.end}|${h.event.memberName ?? ''}|${h.event.address ?? ''}';
        final rank =
            hiddenOrder[eventId.isNotEmpty
                ? 'id:$eventId'
                : 'k:$fallbackKey'] ??
            0;
        borders.add(
          _BorderOverlay(
            weekDay: group.weekDay,
            start: h.range.start,
            end: h.range.end,
            event: h.event,
            insetLevel: borderInsetLevelFor(h),
            priorityRank: rank,
            group: group,
          ),
        );
      }
    }

    return _ConflictRenderPlan(cards: cards, borders: borders);
  }

  String _weekDayText(int weekDay) {
    switch (weekDay) {
      case 1:
        return '周一';
      case 2:
        return '周二';
      case 3:
        return '周三';
      case 4:
        return '周四';
      case 5:
        return '周五';
      case 6:
        return '周六';
      case 7:
        return '周日';
      default:
        return '未知';
    }
  }

  String _sessionText(EventItem event) {
    final range = _eventRange(event);
    return '${range.start}-${range.end}节';
  }

  String _safeText(String? raw, {String fallback = '未知'}) {
    final value = (raw ?? '').trim();
    return value.isEmpty ? fallback : value;
  }

  void _showConflictSheet(
    BuildContext context, {
    required _ConflictGroup group,
    required Color closeButtonColor,
  }) {
    final dayText = _weekDayText(group.weekDay);
    final groupRange = _groupRange(group);
    final sessionText = '${groupRange.start}-${groupRange.end}节';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$dayText $sessionText 有 ${group.events.length} 门课程',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '点击课程可查看详情',
                  style: Theme.of(sheetContext).textTheme.bodySmall?.copyWith(
                    color: Theme.of(sheetContext).colorScheme.outline,
                  ),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: group.events.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (itemContext, index) {
                      final event = group.events[index];
                      return ListTile(
                        dense: true,
                        title: Text(_safeText(event.eventName)),
                        subtitle: Text(
                          '${_sessionText(event)}  ·  ${_safeText(event.address)}\n'
                          '${_safeText(event.memberName)}',
                        ),
                        isThreeLine: true,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          final key = _buildCourseKey(event);
                          showCourseDetailDialog(
                            context,
                            courseName: key,
                            events: _eventsWithSameCourseName(event),
                            closeButtonColor: closeButtonColor,
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
        final conflictGroups = _buildConflictGroups(visibleEvents);
        final renderPlan = _buildRenderPlan(conflictGroups);
        final sortedBorders = List<_BorderOverlay>.from(renderPlan.borders)
          ..sort((a, b) {
            final byDay = a.weekDay.compareTo(b.weekDay);
            if (byDay != 0) return byDay;
            final byDuration = b.duration.compareTo(a.duration);
            if (byDuration != 0) return byDuration;
            final byStart = a.start.compareTo(b.start);
            if (byStart != 0) return byStart;
            return a.insetLevel.compareTo(b.insetLevel);
          });

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
              else ...[
                ...renderPlan.cards.map((card) {
                  final event = card.event;
                  final int weekDay = card.weekDay;
                  final int start = card.start;
                  final int duration = card.end - card.start + 1;

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
                  final inset = card.visualInset;
                  final rawWidth = dayWidth - inset * 2;
                  final rawHeight = duration * widget.sessionHeight - inset * 2;
                  final cardWidth = rawWidth > 20 ? rawWidth : 20.0;
                  final cardHeight = rawHeight > 16 ? rawHeight : 16.0;

                  return Positioned(
                    left: dayIndex * dayWidth + inset,
                    top: (start - 1) * widget.sessionHeight + inset,
                    width: cardWidth,
                    height: cardHeight,
                    child: ScheduleCourseCard(
                      event: event,
                      backgroundColor: backgroundColor,
                      borderColor: borderColor,
                      titleColor: titleColor,
                      descriptionColor: descriptionColor,
                      conflictCount: card.conflictCount,
                      showDecoration: true,
                      showContent: false,
                      showConflictBadge: false,
                      enableTap: false,
                      onTap: () {
                        if (card.group.events.length > 1) {
                          _showConflictSheet(
                            context,
                            group: card.group,
                            closeButtonColor: widget.buttonColors[safeIndex],
                          );
                        } else {
                          showCourseDetailDialog(
                            context,
                            courseName: key,
                            events: _eventsWithSameCourseName(event),
                            closeButtonColor: widget.buttonColors[safeIndex],
                          );
                        }
                      },
                    ),
                  );
                }),
                ...sortedBorders.map((border) {
                  final int weekDay = border.weekDay;
                  final int start = border.start;
                  final int duration = border.duration;
                  final int dayIndex = weekDay - 1;
                  if (dayIndex < 0 || dayIndex >= dayCount) {
                    return const SizedBox.shrink();
                  }

                  final key = _buildCourseKey(border.event);
                  final int colorIndex =
                      _courseColorIndexMap[key] ?? _fallbackIndexForKey(key);
                  final safeIndex = _safeIndex(colorIndex);
                  final fillAlpha = (200 - border.priorityRank * 18).clamp(
                    95,
                    210,
                  );
                  final frameAlpha = (240 - border.priorityRank * 12).clamp(
                    150,
                    245,
                  );
                  final frameWidth = (2.0 - border.priorityRank * 0.2).clamp(
                    1.4,
                    2.0,
                  );
                  final fillColor = widget.backgroundColors[safeIndex]
                      .withAlpha(fillAlpha);
                  final frameColor = widget.borderColors[safeIndex].withAlpha(
                    (frameAlpha + 8).clamp(160, 250),
                  );
                  final inset = 1.0 + border.insetLevel * 2.0;
                  final rawWidth = dayWidth - inset * 2;
                  final rawHeight = duration * widget.sessionHeight - inset * 2;
                  final borderWidth = rawWidth > 6 ? rawWidth : 6.0;
                  final borderHeight = rawHeight > 6 ? rawHeight : 6.0;

                  return Positioned(
                    left: dayIndex * dayWidth + inset,
                    top: (start - 1) * widget.sessionHeight + inset,
                    width: borderWidth,
                    height: borderHeight,
                    child: IgnorePointer(
                      child: Container(
                        margin: EdgeInsets.zero,
                        decoration: BoxDecoration(
                          color: fillColor,
                          border: Border.all(
                            color: frameColor,
                            width: frameWidth,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  );
                }),
                ...renderPlan.cards.map((card) {
                  final event = card.event;
                  final int weekDay = card.weekDay;
                  final int start = card.start;
                  final int duration = card.end - card.start + 1;

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
                  final inset = card.visualInset;
                  final rawWidth = dayWidth - inset * 2;
                  final rawHeight = duration * widget.sessionHeight - inset * 2;
                  final cardWidth = rawWidth > 20 ? rawWidth : 20.0;
                  final cardHeight = rawHeight > 16 ? rawHeight : 16.0;

                  return Positioned(
                    left: dayIndex * dayWidth + inset,
                    top: (start - 1) * widget.sessionHeight + inset,
                    width: cardWidth,
                    height: cardHeight,
                    child: ScheduleCourseCard(
                      event: event,
                      backgroundColor: backgroundColor,
                      borderColor: borderColor,
                      titleColor: titleColor,
                      descriptionColor: descriptionColor,
                      conflictCount: card.conflictCount,
                      showDecoration: false,
                      showContent: true,
                      showConflictBadge: true,
                      enableTap: true,
                      onTap: () {
                        if (card.group.events.length > 1) {
                          _showConflictSheet(
                            context,
                            group: card.group,
                            closeButtonColor: widget.buttonColors[safeIndex],
                          );
                        } else {
                          showCourseDetailDialog(
                            context,
                            courseName: key,
                            events: _eventsWithSameCourseName(event),
                            closeButtonColor: widget.buttonColors[safeIndex],
                          );
                        }
                      },
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _EventRange {
  final int start;
  final int end;

  const _EventRange({required this.start, required this.end});

  int get duration => end - start + 1;
}

class _EventWithRange {
  final EventItem event;
  final _EventRange range;

  const _EventWithRange({required this.event, required this.range});
}

class _ConflictGroup {
  final int weekDay;
  final List<EventItem> events;

  const _ConflictGroup({required this.weekDay, required this.events});
}

class _DisplayCard {
  final int weekDay;
  final int start;
  final int end;
  final EventItem event;
  final int conflictCount;
  final double visualInset;
  final _ConflictGroup group;

  const _DisplayCard({
    required this.weekDay,
    required this.start,
    required this.end,
    required this.event,
    required this.conflictCount,
    required this.visualInset,
    required this.group,
  });
}

class _BorderOverlay {
  final int weekDay;
  final int start;
  final int end;
  final EventItem event;
  final int insetLevel;
  final int priorityRank;
  final _ConflictGroup group;

  const _BorderOverlay({
    required this.weekDay,
    required this.start,
    required this.end,
    required this.event,
    required this.insetLevel,
    required this.priorityRank,
    required this.group,
  });

  int get duration => end - start + 1;
}

class _ConflictRenderPlan {
  final List<_DisplayCard> cards;
  final List<_BorderOverlay> borders;

  const _ConflictRenderPlan({required this.cards, required this.borders});
}
