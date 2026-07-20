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
        final tinyWidth = constraints.maxWidth < 42;
        final compactWidth = constraints.maxWidth < 56;
        final showBadge =
            showConflictBadge &&
            conflictCount > 0 &&
            constraints.maxWidth >= 34 &&
            constraints.maxHeight >= 20;
        final edgeInsets = tinyWidth
            ? const EdgeInsets.symmetric(horizontal: 1, vertical: 1)
            : const EdgeInsets.all(2);
        final lineBudget = _lineBudgetForHeight(constraints.maxHeight);

        final titleText = (event.eventName ?? '').trim();
        final addressText = (event.address ?? '').trim();
        final teacherText = (event.memberName ?? '').trim();

        final titleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: tinyWidth ? 9 : 10,
          fontWeight: FontWeight.bold,
          color: titleColor,
          height: 1.15,
        );
        final detailStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: tinyWidth ? 8 : 9,
          color: descriptionColor,
          height: 1.15,
        );

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
                Padding(
                  padding: EdgeInsets.only(right: showBadge ? 18 : 0),
                  child: SizedBox.expand(
                    child: Text.rich(
                      _buildContentSpan(
                        title: titleText,
                        address: addressText,
                        teacher: teacherText,
                        titleStyle: titleStyle,
                        detailStyle: detailStyle,
                      ),
                      softWrap: true,
                      maxLines: lineBudget,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
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
                        fontSize: compactWidth ? 8 : 9,
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

  TextSpan _buildContentSpan({
    required String title,
    required String address,
    required String teacher,
    required TextStyle? titleStyle,
    required TextStyle? detailStyle,
  }) {
    final children = <InlineSpan>[
      TextSpan(text: title.isEmpty ? '-' : title, style: titleStyle),
    ];

    if (address.isNotEmpty) {
      children.add(TextSpan(text: '\n@$address', style: detailStyle));
    }

    if (teacher.isNotEmpty) {
      children.add(TextSpan(text: '\n$teacher', style: detailStyle));
    }

    return TextSpan(children: children);
  }

  int _lineBudgetForHeight(double height) {
    if (height < 28) return 1;
    if (height < 42) return 2;
    if (height < 58) return 3;
    if (height < 74) return 4;
    if (height < 90) return 5;
    if (height < 108) return 6;
    return 7;
  }
}
