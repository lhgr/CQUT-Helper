import 'package:flutter/material.dart';
import '../../../model/schedule_model.dart';

class ScheduleHeader extends StatelessWidget {
  final ScheduleData scheduleData;
  final double height;
  final double timeColumnWidth;

  const ScheduleHeader({
    Key? key,
    required this.scheduleData,
    this.height = 50.0,
    this.timeColumnWidth = 30.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final weekDayList = scheduleData.weekDayList ?? [];
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(color: colorScheme.outlineVariant, width: 1),
        ),
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
                return Expanded(
                  child: Container(
                    decoration: isToday
                        ? BoxDecoration(
                            color: colorScheme.primaryContainer.withOpacity(
                              0.3,
                            ),
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
