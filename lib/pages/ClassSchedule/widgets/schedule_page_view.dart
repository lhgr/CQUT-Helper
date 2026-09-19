import 'dart:math' as math;

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_grid.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_header.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_time_column.dart';
import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:cqut_helper/utils/academic_calendar_resolver.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:flutter/material.dart';

class SchedulePageView extends StatefulWidget {
  final PageController? pageController;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<bool> onScrollActivityChanged;
  final List<String> weekList;
  final Map<int, ScheduleData> weekCache;
  final bool showWeekend;
  final bool weekendNoticeDismissed;
  final VoidCallback onDismissWeekendNotice;
  final AcademicCalendarSnapshot? academicCalendar;
  final Function(String) onBoundaryMessage;
  final int currentWeekIndex;
  final List<CampusTimeInfo>? timeInfoList;
  final ScheduleLayoutSettings layoutSettings;
  final CourseDetailEventsResolver? resolveCourseDetailEvents;
  final Future<void> Function(EventItem event) onEditCourse;
  final Future<void> Function(EventItem event) onDeleteCourse;

  static const double _headerHeight = 50.0;
  static const double _timeColumnWidth =
      35.0; // Increased width for time labels

  const SchedulePageView({
    super.key,
    required this.pageController,
    required this.onPageChanged,
    required this.onScrollActivityChanged,
    required this.weekList,
    required this.weekCache,
    required this.showWeekend,
    required this.weekendNoticeDismissed,
    required this.onDismissWeekendNotice,
    this.academicCalendar,
    required this.onBoundaryMessage,
    required this.currentWeekIndex,
    this.timeInfoList,
    this.layoutSettings = const ScheduleLayoutSettings(),
    this.resolveCourseDetailEvents,
    required this.onEditCourse,
    required this.onDeleteCourse,
  });

  @override
  State<SchedulePageView> createState() => _SchedulePageViewState();
}

class _SchedulePageViewState extends State<SchedulePageView> {
  @override
  Widget build(BuildContext context) {
    final cardTheme =
        Theme.of(context).extension<ScheduleCourseCardTheme>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ScheduleCourseCardTheme.dark()
            : ScheduleCourseCardTheme.light());

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        if (notification is ScrollStartNotification) {
          widget.onScrollActivityChanged(true);
        } else if (notification is ScrollEndNotification) {
          widget.onScrollActivityChanged(false);
        }
        if (notification is OverscrollNotification) {
          if (notification.overscroll < 0) {
            if (widget.currentWeekIndex == 0) {
              widget.onBoundaryMessage("已经是第一周了");
            }
          } else if (notification.overscroll > 0) {
            if (widget.currentWeekIndex == widget.weekList.length - 1) {
              widget.onBoundaryMessage("已经是最后一周了");
            }
          }
        }
        return false;
      },
      child: PageView.builder(
        controller: widget.pageController,
        onPageChanged: widget.onPageChanged,
        itemCount: widget.weekList.length,
        itemBuilder: (context, index) {
          final weekStr = widget.weekList[index];
          final weekNum = int.tryParse(weekStr) ?? 0;
          final data = widget.weekCache[weekNum];

          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return RepaintBoundary(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final resolved = _resolveWeek(data);
                final displayWeekdays = <EventItem, int>{};
                final displaySources = <EventItem, EventItem>{};
                final disabledDisplayEvents = <EventItem>{};
                final resolvedEvents = resolved.isEmpty
                    ? (data.eventList ?? const <EventItem>[])
                    : [
                        for (final day in resolved.values)
                          for (final item in day.events)
                            _copyForDisplay(
                              item,
                              day.actualDate.weekday,
                              displayWeekdays,
                              displaySources,
                              disabledDisplayEvents,
                              disabled: day.isHoliday,
                            ),
                      ];
                final showMappedWeekend = resolved.values.any(
                  (day) => day.isTeachingDay && day.actualDate.weekday >= 6,
                );
                final effectiveShowWeekend =
                    widget.showWeekend || showMappedWeekend;
                final dayCount = effectiveShowWeekend ? 7 : 5;
                final gridWidth = math.max(
                  widget.layoutSettings.gridCellWidth * dayCount,
                  constraints.maxWidth - SchedulePageView._timeColumnWidth,
                );
                final contentWidth =
                    SchedulePageView._timeColumnWidth + gridWidth;

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: contentWidth,
                    child: Column(
                      children: [
                        ScheduleHeader(
                          scheduleData: data,
                          height: SchedulePageView._headerHeight,
                          timeColumnWidth: SchedulePageView._timeColumnWidth,
                          showWeekend: effectiveShowWeekend,
                          resolvedDays: resolved,
                          showGridLines: widget.layoutSettings.showGridLines,
                          gridLineOpacity:
                              widget.layoutSettings.gridLineOpacity,
                          transparentBackground:
                              widget.layoutSettings.backgroundImagePath != null,
                        ),
                        if (!widget.showWeekend &&
                            showMappedWeekend &&
                            !widget.weekendNoticeDismissed)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            color: Theme.of(
                              context,
                            ).colorScheme.primaryContainer.withAlpha(150),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '本周有周末补课，已临时显示周末课表',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.labelSmall,
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                IconButton(
                                  onPressed: widget.onDismissWeekendNotice,
                                  icon: const Icon(Icons.close, size: 14),
                                  tooltip: '关闭全部周末补课提示',
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints.tightFor(
                                    width: 18,
                                    height: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ScheduleTimeColumn(
                                  width: SchedulePageView._timeColumnWidth,
                                  sessionHeight:
                                      widget.layoutSettings.gridCellHeight,
                                  timeInfoList: widget.timeInfoList,
                                  showGridLines:
                                      widget.layoutSettings.showGridLines,
                                  gridLineOpacity:
                                      widget.layoutSettings.gridLineOpacity,
                                  transparentBackground:
                                      widget
                                          .layoutSettings
                                          .backgroundImagePath !=
                                      null,
                                ),
                                SizedBox(
                                  width: gridWidth,
                                  child: ScheduleCourseGrid(
                                    events: resolvedEvents,
                                    displayWeekdays: displayWeekdays,
                                    disabledEvents: disabledDisplayEvents,
                                    yearTerm: data.yearTerm ?? '',
                                    sessionHeight:
                                        widget.layoutSettings.gridCellHeight,
                                    showWeekend: effectiveShowWeekend,
                                    showGridLines:
                                        widget.layoutSettings.showGridLines,
                                    gridLineOpacity:
                                        widget.layoutSettings.gridLineOpacity,
                                    hideLocation:
                                        widget.layoutSettings.hideLocation,
                                    hideTeacher:
                                        widget.layoutSettings.hideTeacher,
                                    removeCampusPrefix: widget
                                        .layoutSettings
                                        .removeCampusPrefix,
                                    horizontalCenter:
                                        widget.layoutSettings.horizontalCenter,
                                    verticalCenter:
                                        widget.layoutSettings.verticalCenter,
                                    cardRadius:
                                        widget.layoutSettings.cardRadius,
                                    textScale: widget.layoutSettings.textScale,
                                    cardOpacity:
                                        widget.layoutSettings.cardOpacity,
                                    backgroundColors: cardTheme.backgrounds,
                                    borderColors: cardTheme.borders,
                                    titleColors: cardTheme.titleColors,
                                    descriptionColors:
                                        cardTheme.descriptionColors,
                                    buttonColors: cardTheme.buttonColors,
                                    resolveCourseDetailEvents:
                                        widget.resolveCourseDetailEvents == null
                                        ? null
                                        : (event) =>
                                              widget.resolveCourseDetailEvents!(
                                                displaySources[event] ?? event,
                                              ),
                                    onEditCourse: (event) =>
                                        widget.onEditCourse(
                                          displaySources[event] ?? event,
                                        ),
                                    onDeleteCourse: (event) =>
                                        widget.onDeleteCourse(
                                          displaySources[event] ?? event,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  EventItem _copyForDisplay(
    AcademicCalendarResolvedEvent resolved,
    int actualWeekday,
    Map<EventItem, int> displayWeekdays,
    Map<EventItem, EventItem> displaySources,
    Set<EventItem> disabledDisplayEvents, {
    required bool disabled,
  }) {
    final originalNote = (resolved.event.note ?? '').trim();
    final mappingNote = resolved.isMapped
        ? '调休：原${academicCalendarDateKey(resolved.sourceDate)}课程'
        : null;
    final copy = EventItem.fromJson({
      ...resolved.event.toJson(),
      'weekDay': actualWeekday.toString(),
      if (mappingNote != null)
        'note': [
          if (originalNote.isNotEmpty) originalNote,
          mappingNote,
        ].join(' · '),
    });
    displayWeekdays[copy] = actualWeekday;
    displaySources[copy] = resolved.event;
    if (disabled) disabledDisplayEvents.add(copy);
    return copy;
  }

  Map<String, AcademicCalendarResolvedDay> _resolveWeek(ScheduleData data) {
    final days = data.weekDayList ?? const <WeekDayItem>[];
    final schedules = widget.weekCache.values;
    final result = <String, AcademicCalendarResolvedDay>{};
    for (final item in days) {
      final date = ScheduleDate.tryParseWeekDate(item.weekDate);
      if (date == null) continue;
      final resolved = resolveAcademicCalendarDay(
        actualDate: date,
        schedules: schedules,
        calendar: widget.academicCalendar,
        includeHolidayEvents: true,
      );
      result[academicCalendarDateKey(date)] = resolved;
    }
    return result;
  }
}
