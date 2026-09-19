import 'package:flutter/material.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/academic_calendar_resolver.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:cqut_helper/theme/schedule_grid_line_theme.dart';

class ScheduleHeader extends StatelessWidget {
  final ScheduleData scheduleData;
  final double height;
  final double timeColumnWidth;
  final bool showWeekend;
  final bool showGridLines;
  final double gridLineOpacity;
  final bool transparentBackground;
  final Map<String, AcademicCalendarResolvedDay> resolvedDays;

  const ScheduleHeader({
    super.key,
    required this.scheduleData,
    this.height = 50.0,
    this.timeColumnWidth = 30.0,
    this.showWeekend = true,
    this.showGridLines = true,
    this.gridLineOpacity = 0.2,
    this.transparentBackground = false,
    this.resolvedDays = const <String, AcademicCalendarResolvedDay>{},
  });

  @override
  Widget build(BuildContext context) {
    final weekDayListAll = scheduleData.weekDayList ?? [];
    final weekDayList = showWeekend ? weekDayListAll : weekDayListAll.take(5);
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: transparentBackground ? Colors.transparent : colorScheme.surface,
        border: showGridLines
            ? Border(
                bottom: BorderSide(
                  color: scheduleGridLineColor(context, gridLineOpacity),
                  width: 1,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: timeColumnWidth,
            child: Center(
              child: Text(
                "${scheduleData.nowMonth}\n月",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: Row(
              children: weekDayList.map((day) {
                final isToday = day.today == true;
                final date = ScheduleDate.tryParseWeekDate(day.weekDate);
                final resolved = date == null
                    ? null
                    : resolvedDays[academicCalendarDateKey(date)];
                final marker = resolved?.isHoliday == true
                    ? '休'
                    : resolved?.isTeachingDay == true
                    ? '调'
                    : null;
                return Expanded(
                  child: Container(
                    decoration: isToday
                        ? BoxDecoration(
                            color: colorScheme.primaryContainer.withAlpha(77),
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          )
                        : null,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "周${day.weekDay}",
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                fontWeight: isToday
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isToday
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                        ),
                        SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              day.weekDate ?? "",
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: 10,
                                    color: isToday
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            if (marker != null) ...[
                              const SizedBox(width: 3),
                              Text(
                                marker,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: resolved?.isHoliday == true
                                          ? colorScheme.error
                                          : colorScheme.primary,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
