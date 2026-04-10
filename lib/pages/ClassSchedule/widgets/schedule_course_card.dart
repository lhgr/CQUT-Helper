import 'package:cqut/model/class_schedule_model.dart';
import 'package:flutter/material.dart';

class ScheduleCourseCard extends StatelessWidget {
  final EventItem event;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color descriptionColor;
  final VoidCallback onTap;

  const ScheduleCourseCard({
    super.key,
    required this.event,
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.descriptionColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor, width: 1),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(13),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.eventName ?? "",
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: titleColor,
                  ),
              maxLines: 3,
              overflow: TextOverflow.visible,
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                "@${event.address}",
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontSize: 9,
                      color: descriptionColor,
                    ),
                maxLines: null,
                overflow: TextOverflow.visible,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              event.memberName ?? "",
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 9,
                    color: descriptionColor,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
