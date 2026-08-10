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
  final bool hideLocation;
  final bool hideTeacher;
  final bool removeCampusPrefix;
  final bool horizontalCenter;
  final bool verticalCenter;
  final double borderRadius;
  final double textScale;
  final double cardOpacity;

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
    this.hideLocation = false,
    this.hideTeacher = false,
    this.removeCampusPrefix = false,
    this.horizontalCenter = false,
    this.verticalCenter = false,
    this.borderRadius = 12,
    this.textScale = 1,
    this.cardOpacity = 1,
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
        final rawAddress = (event.address ?? '').trim();
        final addressText = hideLocation
            ? ''
            : removeCampusPrefix
            ? removeKnownCampusPrefix(rawAddress)
            : rawAddress;
        final teacherText = hideTeacher ? '' : (event.memberName ?? '').trim();

        final titleStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          fontSize: (tinyWidth ? 9 : 10) * textScale,
          fontWeight: FontWeight.bold,
          color: titleColor,
          height: 1.15,
        );
        final detailStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontSize: (tinyWidth ? 8 : 9) * textScale,
          color: descriptionColor,
          height: 1.15,
        );

        return Container(
          margin: const EdgeInsets.all(1),
          padding: edgeInsets,
          decoration: showDecoration
              ? BoxDecoration(
                  color: backgroundColor.withAlpha(
                    (backgroundColor.a * 255 * cardOpacity).round().clamp(
                      0,
                      255,
                    ),
                  ),
                  border: Border.all(color: borderColor, width: 1),
                  borderRadius: BorderRadius.circular(borderRadius),
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
                    child: Align(
                      alignment: verticalCenter
                          ? (horizontalCenter
                                ? Alignment.center
                                : Alignment.centerLeft)
                          : (horizontalCenter
                                ? Alignment.topCenter
                                : Alignment.topLeft),
                      child: Text.rich(
                        _buildContentSpan(
                          title: titleText,
                          address: addressText,
                          teacher: teacherText,
                          prefixAddressWithAt: !removeCampusPrefix,
                          titleStyle: titleStyle,
                          detailStyle: detailStyle,
                        ),
                        softWrap: true,
                        textAlign: horizontalCenter
                            ? TextAlign.center
                            : TextAlign.start,
                        maxLines: lineBudget,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  @visibleForTesting
  static String removeKnownCampusPrefix(String address) {
    return address
        .replaceFirst(RegExp(r'^(花溪校区|两江校区)\s*[-—·:：]?\s*'), '')
        .trim();
  }

  TextSpan _buildContentSpan({
    required String title,
    required String address,
    required String teacher,
    required bool prefixAddressWithAt,
    required TextStyle? titleStyle,
    required TextStyle? detailStyle,
  }) {
    final children = <InlineSpan>[
      TextSpan(text: title.isEmpty ? '-' : title, style: titleStyle),
    ];

    if (address.isNotEmpty) {
      final prefix = prefixAddressWithAt ? '@' : '';
      children.add(TextSpan(text: '\n$prefix$address', style: detailStyle));
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
