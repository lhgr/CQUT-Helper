import 'package:cqut/model/class_schedule_model.dart';
import 'package:flutter/material.dart';

class ScheduleTimeColumn extends StatelessWidget {
  final double width;
  final double sessionHeight;
  final int sessionCount;
  final List<CampusTimeInfo>? timeInfoList;

  const ScheduleTimeColumn({
    super.key,
    this.width = 35.0,
    this.sessionHeight = 60.0,
    this.sessionCount = 12,
    this.timeInfoList,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: List.generate(sessionCount, (index) {
          final sessionNum = index + 1;
          String? start;
          String? end;
          if (timeInfoList != null) {
            try {
              final info = timeInfoList!.firstWhere(
                (element) => element.sessionNum == sessionNum,
              );
              start = info.startTime;
              end = info.endTime;
            } catch (_) {}
          }

          return Container(
            height: sessionHeight,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (start != null)
                  Text(
                    start,
                    style: TextStyle(
                      fontSize: 8,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  "$sessionNum",
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (end != null)
                  Text(
                    end,
                    style: TextStyle(
                      fontSize: 8,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
