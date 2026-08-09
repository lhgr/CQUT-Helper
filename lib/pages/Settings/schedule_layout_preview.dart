import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_course_card.dart';
import 'package:cqut_helper/theme/schedule_course_card_theme.dart';
import 'package:flutter/material.dart';

class ScheduleLayoutPreview extends StatelessWidget {
  final ScheduleLayoutSettings settings;
  final bool showWeekend;
  final bool timeInfoEnabled;

  const ScheduleLayoutPreview({
    super.key,
    required this.settings,
    required this.showWeekend,
    required this.timeInfoEnabled,
  });

  static const _timeWidth = 34.0;
  static const _headerHeight = 38.0;
  static const _sessionCount = 6;

  @override
  Widget build(BuildContext context) {
    final cardTheme =
        Theme.of(context).extension<ScheduleCourseCardTheme>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ScheduleCourseCardTheme.dark()
            : ScheduleCourseCardTheme.light());
    final dayCount = showWeekend ? 7 : 5;

    return LayoutBuilder(
      builder: (context, constraints) {
        final gridWidth = math.max(
          settings.gridCellWidth * dayCount,
          constraints.maxWidth - _timeWidth,
        );
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: SizedBox(
              height: 310,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _PreviewBackground(settings: settings),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: _timeWidth + gridWidth,
                      child: Column(
                        children: [
                          _PreviewHeader(
                            dayCount: dayCount,
                            gridWidth: gridWidth,
                            showGridLines: settings.showGridLines,
                          ),
                          Expanded(
                            child: SingleChildScrollView(
                              child: SizedBox(
                                height: settings.gridCellHeight * _sessionCount,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _PreviewTimeColumn(
                                      rowHeight: settings.gridCellHeight,
                                      showTimes: timeInfoEnabled,
                                      showGridLines: settings.showGridLines,
                                    ),
                                    SizedBox(
                                      width: gridWidth,
                                      child: _PreviewGrid(
                                        settings: settings,
                                        dayCount: dayCount,
                                        gridWidth: gridWidth,
                                        cardTheme: cardTheme,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PreviewBackground extends StatelessWidget {
  final ScheduleLayoutSettings settings;

  const _PreviewBackground({required this.settings});

  @override
  Widget build(BuildContext context) {
    final path = settings.backgroundImagePath?.trim();
    if (path == null || path.isEmpty || !File(path).existsSync()) {
      return ColoredBox(color: Theme.of(context).colorScheme.surface);
    }
    return ClipRect(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: settings.backgroundBlur,
          sigmaY: settings.backgroundBlur,
        ),
        child: Opacity(
          opacity: settings.backgroundOpacity,
          child: Image.file(File(path), fit: BoxFit.cover),
        ),
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  final int dayCount;
  final double gridWidth;
  final bool showGridLines;

  const _PreviewHeader({
    required this.dayCount,
    required this.gridWidth,
    required this.showGridLines,
  });

  @override
  Widget build(BuildContext context) {
    const days = ['一', '二', '三', '四', '五', '六', '日'];
    final surface = Theme.of(context).colorScheme.surface.withAlpha(225);
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      height: ScheduleLayoutPreview._headerHeight,
      color: surface,
      child: Row(
        children: [
          const SizedBox(
            width: ScheduleLayoutPreview._timeWidth,
            child: Center(child: Text('9月', style: TextStyle(fontSize: 10))),
          ),
          SizedBox(
            width: gridWidth,
            child: Row(
              children: List.generate(
                dayCount,
                (index) => Expanded(
                  child: Container(
                    decoration: showGridLines
                        ? BoxDecoration(
                            border: Border(
                              left: BorderSide(color: borderColor, width: .5),
                              bottom: BorderSide(color: borderColor, width: .5),
                            ),
                          )
                        : null,
                    alignment: Alignment.center,
                    child: Text(
                      '周${days[index]}',
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewTimeColumn extends StatelessWidget {
  final double rowHeight;
  final bool showTimes;
  final bool showGridLines;

  const _PreviewTimeColumn({
    required this.rowHeight,
    required this.showTimes,
    required this.showGridLines,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Container(
      width: ScheduleLayoutPreview._timeWidth,
      color: Theme.of(context).colorScheme.surface.withAlpha(225),
      child: Column(
        children: List.generate(
          ScheduleLayoutPreview._sessionCount,
          (index) => Container(
            height: rowHeight,
            decoration: showGridLines
                ? BoxDecoration(
                    border: Border(
                      right: BorderSide(color: borderColor, width: .5),
                      bottom: BorderSide(color: borderColor, width: .5),
                    ),
                  )
                : null,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showTimes)
                  Text('${8 + index}:00', style: const TextStyle(fontSize: 7)),
                Text('${index + 1}', style: const TextStyle(fontSize: 10)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewGrid extends StatelessWidget {
  final ScheduleLayoutSettings settings;
  final int dayCount;
  final double gridWidth;
  final ScheduleCourseCardTheme cardTheme;

  const _PreviewGrid({
    required this.settings,
    required this.dayCount,
    required this.gridWidth,
    required this.cardTheme,
  });

  static final _cards = <_PreviewCardSpec>[
    _PreviewCardSpec(
      day: 1,
      start: 1,
      duration: 2,
      color: 0,
      event: EventItem(
        eventName: '高等数学',
        address: '花溪校区 博园201',
        memberName: '张老师',
      ),
    ),
    _PreviewCardSpec(
      day: 3,
      start: 2,
      duration: 3,
      color: 2,
      event: EventItem(
        eventName: '程序设计基础',
        address: '两江校区·弘远楼A103',
        memberName: '李老师',
      ),
    ),
    _PreviewCardSpec(
      day: 5,
      start: 4,
      duration: 2,
      color: 3,
      event: EventItem(eventName: '大学英语', address: '明理楼301', memberName: '王老师'),
    ),
    _PreviewCardSpec(
      day: 6,
      start: 1,
      duration: 2,
      color: 5,
      event: EventItem(eventName: '创新实践', address: '实验中心', memberName: '陈老师'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final dayWidth = gridWidth / dayCount;
    final borderColor = Theme.of(context).colorScheme.outlineVariant;
    return Stack(
      children: [
        if (settings.showGridLines)
          ...List.generate(
            ScheduleLayoutPreview._sessionCount,
            (index) => Positioned(
              top: index * settings.gridCellHeight,
              left: 0,
              right: 0,
              height: settings.gridCellHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: borderColor, width: .5),
                  ),
                ),
              ),
            ),
          ),
        if (settings.showGridLines)
          ...List.generate(
            dayCount,
            (index) => Positioned(
              left: index * dayWidth,
              top: 0,
              bottom: 0,
              width: dayWidth,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(
                    right: BorderSide(color: borderColor, width: .5),
                  ),
                ),
              ),
            ),
          ),
        ..._cards.where((card) => card.day <= dayCount).map((card) {
          final index = card.color % cardTheme.backgrounds.length;
          return Positioned(
            left: (card.day - 1) * dayWidth + 1,
            top: (card.start - 1) * settings.gridCellHeight + 1,
            width: dayWidth - 2,
            height: settings.gridCellHeight * card.duration - 2,
            child: ScheduleCourseCard(
              event: card.event,
              backgroundColor: cardTheme.backgroundAt(index),
              borderColor: cardTheme.borderAt(index),
              titleColor: cardTheme.titleAt(index),
              descriptionColor: cardTheme.descriptionAt(index),
              onTap: () {},
              enableTap: false,
              hideLocation: settings.hideLocation,
              hideTeacher: settings.hideTeacher,
              removeCampusPrefix: settings.removeCampusPrefix,
              horizontalCenter: settings.horizontalCenter,
              verticalCenter: settings.verticalCenter,
              borderRadius: settings.cardRadius,
              textScale: settings.textScale,
            ),
          );
        }),
      ],
    );
  }
}

class _PreviewCardSpec {
  final int day;
  final int start;
  final int duration;
  final int color;
  final EventItem event;

  const _PreviewCardSpec({
    required this.day,
    required this.start,
    required this.duration,
    required this.color,
    required this.event,
  });
}
