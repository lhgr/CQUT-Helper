import 'package:flutter/material.dart';
import '../models/schedule_week_change.dart';
import '../models/class_schedule_model.dart';

void showScheduleChangesSheet({
  required BuildContext context,
  required List<ScheduleWeekChange> changes,
  required Function(String) onJumpToWeek,
  required ScheduleData? currentScheduleData,
  required List<String>? weekList,
}) {
  String labelForWeek(String week) {
    final currentWeek = currentScheduleData?.weekNum;
    if (currentWeek != null && week == currentWeek) return '本周';
    if (weekList != null &&
        currentWeek != null &&
        weekList.indexOf(week) == weekList.indexOf(currentWeek) + 1) {
      return '下周';
    }
    return '第$week周';
  }

  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: changes.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final c = changes[index];
              final title = '${labelForWeek(c.weekNum)}变更';
              final lines = c.lines.isEmpty
                  ? const ['课表有更新（无法解析具体变更）']
                  : c.lines;

              return Material(
                color: Theme.of(context).colorScheme.surface,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.pop(context);
                            onJumpToWeek(c.weekNum);
                          },
                          child: Text('跳转'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...lines.map(
                      (t) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text('· $t'),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  );
}
