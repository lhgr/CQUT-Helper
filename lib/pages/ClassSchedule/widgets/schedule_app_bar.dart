import 'package:cqut/model/class_schedule_model.dart';
import 'package:flutter/material.dart';

class ScheduleAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool loading;
  final List<String>? weekList;
  final int currentWeekIndex;
  final ScheduleData? currentScheduleData;
  final bool? nowInTeachingWeek;
  final String? nowStatusLabel;
  final VoidCallback onRefresh;
  final VoidCallback onSettings;
  final VoidCallback onWeekPicker;
  final VoidCallback onTermPicker;

  const ScheduleAppBar({
    super.key,
    required this.loading,
    required this.weekList,
    required this.currentWeekIndex,
    required this.currentScheduleData,
    this.nowInTeachingWeek,
    this.nowStatusLabel,
    required this.onRefresh,
    required this.onSettings,
    required this.onWeekPicker,
    required this.onTermPicker,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      scrolledUnderElevation: 0,
      backgroundColor: Theme.of(context).colorScheme.surface,
      actions: [
        IconButton(
          onPressed: loading ? null : onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          onPressed: onSettings,
          icon: const Icon(Icons.tune),
          tooltip: '课表设置',
        ),
      ],
      title: Column(
        children: [
          InkWell(
            onTap: onWeekPicker,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 8.0,
                vertical: 2.0,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    (nowInTeachingWeek == false &&
                            nowStatusLabel != null &&
                            nowStatusLabel!.isNotEmpty &&
                            weekList != null &&
                            currentWeekIndex < weekList!.length)
                        ? "$nowStatusLabel · 第${weekList![currentWeekIndex]}周"
                        : (weekList != null &&
                                currentWeekIndex < weekList!.length)
                            ? "第${weekList![currentWeekIndex]}周"
                            : "课表",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
          if (currentScheduleData != null)
            InkWell(
              onTap: onTermPicker,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8.0,
                  vertical: 2.0,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "${currentScheduleData!.yearTerm}学期",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 16,
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      centerTitle: true,
    );
  }
}
