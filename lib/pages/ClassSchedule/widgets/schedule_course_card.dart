import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:material_ui/material_ui.dart';

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
        final expandedConflictBadge = constraints.maxWidth >= 68;
        final showBadge =
            showConflictBadge &&
            conflictCount > 0 &&
            constraints.maxWidth >= 34 &&
            constraints.maxHeight >= 20;
        final edgeInsets = tinyWidth
            ? const EdgeInsets.symmetric(horizontal: 1, vertical: 1)
            : const EdgeInsets.all(2);

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

        final contents = Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            if (showContent)
              Padding(
                padding: showBadge
                    ? expandedConflictBadge
                          ? const EdgeInsets.only(top: 14)
                          : const EdgeInsets.only(right: 24)
                    : EdgeInsets.zero,
                child: SizedBox.expand(
                  child: Align(
                    alignment: verticalCenter
                        ? (horizontalCenter
                              ? Alignment.center
                              : Alignment.centerLeft)
                        : (horizontalCenter
                              ? Alignment.topCenter
                              : Alignment.topLeft),
                    child: _buildContent(
                      context,
                      title: titleText.isEmpty ? '-' : titleText,
                      address: addressText.isEmpty
                          ? ''
                          : '${removeCampusPrefix ? '' : '@'}$addressText',
                      addressSemanticLabel: '地点：$rawAddress',
                      teacher: teacherText,
                      titleStyle: titleStyle!,
                      detailStyle: detailStyle!,
                      width:
                          constraints.maxWidth -
                          2 -
                          edgeInsets.horizontal -
                          (showBadge && !expandedConflictBadge ? 24 : 0),
                      height:
                          constraints.maxHeight -
                          2 -
                          edgeInsets.vertical -
                          (showBadge && expandedConflictBadge ? 14 : 0),
                    ),
                  ),
                ),
              ),
            if (showBadge)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  key: conflictIndicatorKeyForEvent(event),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 3,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: borderColor.withAlpha(230),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: compactWidth ? 9 : 10,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 1),
                      Text(
                        expandedConflictBadge
                            ? '冲突 +$conflictCount'
                            : '+$conflictCount',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontSize: compactWidth ? 8 : 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
        final paddedContents = Padding(padding: edgeInsets, child: contents);
        final interactiveContents = enableTap
            ? InkWell(
                key: interactionKeyForEvent(event),
                onTap: onTap,
                borderRadius: BorderRadius.circular(borderRadius),
                splashColor: titleColor.withAlpha(42),
                highlightColor: titleColor.withAlpha(24),
                child: paddedContents,
              )
            : paddedContents;
        return Padding(
          padding: const EdgeInsets.all(1),
          child: Material(
            type: MaterialType.transparency,
            borderRadius: BorderRadius.circular(borderRadius),
            clipBehavior: Clip.antiAlias,
            child: Ink(
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
              child: interactiveContents,
            ),
          ),
        );
      },
    );
    return card;
  }

  @visibleForTesting
  static ValueKey<String> interactionKeyForEvent(EventItem event) =>
      ValueKey('schedule-course-card:${_stableEventIdentity(event)}');

  @visibleForTesting
  static ValueKey<String> conflictIndicatorKeyForEvent(EventItem event) =>
      ValueKey('schedule-course-conflict:${_stableEventIdentity(event)}');

  static String _stableEventIdentity(EventItem event) {
    final eventId = (event.eventID ?? '').trim();
    if (eventId.isNotEmpty) return 'id:$eventId';
    return [
      (event.eventName ?? '').trim(),
      (event.weekNum ?? '').trim(),
      (event.weekDay ?? '').trim(),
      (event.sessionStart ?? '').trim(),
      (event.sessionLast ?? '').trim(),
      (event.memberName ?? '').trim(),
    ].join('|');
  }

  @visibleForTesting
  static String removeKnownCampusPrefix(String address) {
    return address
        .replaceFirst(RegExp(r'^(花溪校区|两江校区)\s*[-—·:：]?\s*'), '')
        .trim();
  }

  Widget _buildContent(
    BuildContext context, {
    required String title,
    required String address,
    required String addressSemanticLabel,
    required String teacher,
    required TextStyle titleStyle,
    required TextStyle detailStyle,
    required double width,
    required double height,
  }) {
    if (width <= 0 || height <= 0) return const SizedBox.shrink();
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    final defaults = DefaultTextStyle.of(context);
    TextStyle resolvedStyle(TextStyle style) {
      final resolved = defaults.style.merge(style);
      return MediaQuery.boldTextOf(context)
          ? resolved.copyWith(fontWeight: FontWeight.bold)
          : resolved;
    }

    titleStyle = resolvedStyle(titleStyle);
    detailStyle = resolvedStyle(detailStyle);
    TextPainter measure(String text, TextStyle style) => TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      locale: Localizations.maybeLocaleOf(context),
      textHeightBehavior: defaults.textHeightBehavior,
    )..layout(maxWidth: width);
    final titleMetrics = measure(title, titleStyle);
    final addressMetrics = measure(address, detailStyle);
    final titleProbe = measure('国', titleStyle);
    final detailProbe = measure('国', detailStyle);
    final lineHeight = titleProbe.height > detailProbe.height
        ? titleProbe.height
        : detailProbe.height;
    titleProbe.dispose();
    detailProbe.dispose();
    // Reserve location before giving long names additional lines.
    final budget = (height / lineHeight).floor().clamp(1, 7);
    final titleNeeded = titleMetrics.computeLineMetrics().length.clamp(1, 3);
    final addressNeeded = address.isEmpty
        ? 0
        : addressMetrics.computeLineMetrics().length.clamp(1, 3);
    titleMetrics.dispose();
    addressMetrics.dispose();
    var titleLines = 1;
    var addressLines = addressNeeded > 0 && budget >= 2 ? 1 : 0;
    var remaining = budget - titleLines - addressLines;
    final extraTitle = (titleNeeded - titleLines).clamp(0, remaining);
    titleLines += extraTitle;
    remaining -= extraTitle;
    if (addressLines > 0) {
      final extraAddress = (addressNeeded - addressLines).clamp(0, remaining);
      addressLines += extraAddress;
      remaining -= extraAddress;
    }
    bool addressFits(String value, int lines) {
      final painter = TextPainter(
        text: TextSpan(text: value, style: detailStyle),
        textDirection: direction,
        textScaler: scaler,
        locale: Localizations.maybeLocaleOf(context),
        textHeightBehavior: defaults.textHeightBehavior,
        maxLines: lines,
      )..layout(maxWidth: width);
      final result = !painter.didExceedMaxLines;
      painter.dispose();
      return result;
    }

    final roomToken = RegExp(r'[A-Za-z]?\d+[A-Za-z]?$')
        .firstMatch(address)
        ?.group(0);
    // Give a room number enough lines before spending them on a third title line.
    while (addressLines > 0 &&
        roomToken != null &&
        !addressFits(roomToken, addressLines) &&
        (remaining > 0 || titleLines > 1)) {
      if (remaining > 0) {
        remaining--;
      } else {
        titleLines--;
      }
      addressLines++;
    }

    String compactAddress(int lines) {
      bool fits(String value) => addressFits(value, lines);

      if (fits(address)) return address;
      if (roomToken != null && fits(roomToken) && !fits('…$roomToken')) {
        return roomToken;
      }
      final points = address.runes.toList(growable: false);
      final roomTokenLength = roomToken?.runes.length ?? 4;
      String candidate(int count) {
        final prefix = (count - roomTokenLength).clamp(0, count) ~/ 3;
        return '${String.fromCharCodes(points.take(prefix))}…${String.fromCharCodes(points.skip(points.length - count + prefix))}';
      }

      var low = 0;
      var high = points.length - 1;
      var result = '…';
      while (low <= high) {
        final count = (low + high) ~/ 2;
        final value = candidate(count);
        if (fits(value)) {
          result = value;
          low = count + 1;
        } else {
          high = count - 1;
        }
      }
      return result;
    }

    Widget field(
      String text,
      TextStyle style,
      int lines, {
      String? semanticLabel,
    }) => Text(
      text,
      semanticsLabel: semanticLabel,
      style: style,
      textAlign: horizontalCenter ? TextAlign.center : TextAlign.start,
      maxLines: lines,
      textHeightBehavior: defaults.textHeightBehavior,
      overflow: TextOverflow.ellipsis,
    );
    return ClipRect(
      child: OverflowBox(
        minHeight: 0,
        maxHeight: double.infinity,
        alignment: verticalCenter ? Alignment.center : Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field(title, titleStyle, titleLines),
              if (addressLines > 0)
                field(
                  compactAddress(addressLines),
                  detailStyle,
                  addressLines,
                  semanticLabel: addressSemanticLabel,
                ),
              if (teacher.isNotEmpty && remaining > 0)
                field(teacher, detailStyle, 1),
            ],
          ),
        ),
      ),
    );
  }
}
