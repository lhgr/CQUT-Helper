import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter/material.dart';

class ScheduleCourseCard extends StatelessWidget {
  final EventItem event;
  final Color backgroundColor;
  final Color borderColor;
  final Color titleColor;
  final Color descriptionColor;
  final VoidCallback onTap;
  final int conflictCount;
  final bool showDecoration;
  final bool showContent;
  final bool showConflictBadge;
  final bool enableTap;

  const ScheduleCourseCard({
    super.key,
    required this.event,
    required this.backgroundColor,
    required this.borderColor,
    required this.titleColor,
    required this.descriptionColor,
    required this.onTap,
    this.conflictCount = 0,
    this.showDecoration = true,
    this.showContent = true,
    this.showConflictBadge = true,
    this.enableTap = true,
  });

  @override
  Widget build(BuildContext context) {
    final card = LayoutBuilder(
      builder: (context, constraints) {
        final compactWidth = constraints.maxWidth < 56;
        final tinyWidth = constraints.maxWidth < 42;
        final compactHeight = constraints.maxHeight < 46;
        final hideTeacher = compactWidth || compactHeight;
        final hideAddress = tinyWidth || constraints.maxHeight < 34;
        final showBadge =
            showConflictBadge &&
            conflictCount > 0 &&
            constraints.maxWidth >= 34 &&
            constraints.maxHeight >= 20;
        final edgeInsets = tinyWidth
            ? const EdgeInsets.symmetric(horizontal: 1, vertical: 1)
            : const EdgeInsets.all(2);

        return Container(
          margin: const EdgeInsets.all(1),
          padding: edgeInsets,
          decoration: showDecoration
              ? BoxDecoration(
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
                )
              : const BoxDecoration(color: Colors.transparent),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (showContent)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.eventName ?? "",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: tinyWidth ? 9 : 10,
                        fontWeight: FontWeight.bold,
                        color: titleColor,
                      ),
                      maxLines: tinyWidth ? 1 : (compactWidth ? 2 : 3),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!hideAddress) const SizedBox(height: 2),
                    if (!hideAddress)
                      Flexible(
                        child: Text(
                          "@${event.address}",
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontSize: tinyWidth ? 8 : 9,
                                color: descriptionColor,
                              ),
                          maxLines: compactWidth ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (!hideTeacher) const SizedBox(height: 2),
                    if (!hideTeacher)
                      Text(
                        event.memberName ?? "",
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: tinyWidth ? 8 : 9,
                          color: descriptionColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              if (showBadge)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: borderColor.withAlpha(230),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+$conflictCount',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
    if (!enableTap) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}
