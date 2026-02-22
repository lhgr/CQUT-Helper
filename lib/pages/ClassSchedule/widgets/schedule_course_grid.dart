import 'package:flutter/material.dart';
import 'package:cqut/model/class_schedule_model.dart';

class ScheduleCourseGrid extends StatelessWidget {
  final List<EventItem> events;
  final double sessionHeight;
  final int sessionCount;
  final List<Color> colors;
  final List<Color> textColors;
  final bool showWeekend;

  const ScheduleCourseGrid({
    super.key,
    required this.events,
    this.sessionHeight = 60.0,
    this.sessionCount = 12,
    required this.colors,
    required this.textColors,
    this.showWeekend = true,
  });

  void _showCourseDetail(BuildContext context, EventItem event) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          icon: Icon(Icons.school_outlined),
          title: Text(
            event.eventName ?? "课程详情",
            style: Theme.of(context).textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                context,
                Icons.room_outlined,
                "教室",
                event.address,
              ),
              _buildDetailRow(
                context,
                Icons.person_outline,
                "教师",
                event.memberName,
              ),
              _buildDetailRow(
                context,
                Icons.calendar_today_outlined,
                "周次",
                event.weekCover,
              ),
              _buildDetailRow(
                context,
                Icons.access_time,
                "节次",
                "${event.sessionStart}-${int.parse(event.sessionStart!) + int.parse(event.sessionLast!) - 1}节",
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("关闭"),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(
    BuildContext context,
    IconData icon,
    String label,
    String? value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
                Text(
                  value ?? "未知",
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final int dayCount = showWeekend ? 7 : 5;
        final double dayWidth = constraints.maxWidth / dayCount;
        final double totalHeight = sessionHeight * sessionCount;
        final visibleEvents = showWeekend
            ? events
            : events.where((event) {
                final weekDay = int.tryParse(event.weekDay ?? '1') ?? 1;
                return weekDay >= 1 && weekDay <= 5;
              }).toList(growable: false);

        return SizedBox(
          height: totalHeight,
          child: Stack(
            children: [
              // Grid lines
              ...List.generate(sessionCount, (index) {
                return Positioned(
                  top: index * sessionHeight,
                  left: 0,
                  right: 0,
                  child: Container(
                    height: sessionHeight,
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

                  final int colorIndex =
                      event.eventName.hashCode % colors.length;
                  final Color backgroundColor = colors[colorIndex];
                  final Color textColor =
                      textColors[colorIndex % textColors.length];

                  return Positioned(
                    left: dayIndex * dayWidth,
                    top: (start - 1) * sessionHeight,
                    width: dayWidth,
                    height: duration * sessionHeight,
                    child: GestureDetector(
                      onTap: () => _showCourseDetail(context, event),
                      child: Container(
                        margin: const EdgeInsets.all(1),
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: backgroundColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha(13),
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.eventName ?? "",
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                              maxLines: 3,
                              overflow: TextOverflow.visible,
                            ),
                            const SizedBox(height: 2),
                            Flexible(
                              child: Text(
                                "@${event.address}",
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      fontSize: 9,
                                      color: textColor.withAlpha(204),
                                    ),
                                maxLines: null,
                                overflow: TextOverflow.visible,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              event.memberName ?? "",
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontSize: 9,
                                    color: textColor.withAlpha(204),
                                  ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
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
