import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_course_grid.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_header.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_time_column.dart';
import 'package:flutter/material.dart';

class SchedulePageView extends StatelessWidget {
  final PageController? pageController;
  final ValueChanged<int> onPageChanged;
  final List<String> weekList;
  final Map<int, ScheduleData> weekCache;
  final bool showWeekend;
  final Function(String) onBoundaryMessage;
  final int currentWeekIndex;
  final List<CampusTimeInfo>? timeInfoList;

  static const double _headerHeight = 50.0;
  static const double _timeColumnWidth =
      35.0; // Increased width for time labels
  static const double _sessionHeight = 60.0;

  static const int _colorCount = 16;
  static const double _goldenAngle = 137.508;

  static List<Color> _buildCourseColors(
    ColorScheme colorScheme,
    Brightness brightness,
  ) {
    final bool isDark = brightness == Brightness.dark;
    final double primaryHue = HSLColor.fromColor(colorScheme.primary).hue;
    final double secondaryHue = HSLColor.fromColor(colorScheme.secondary).hue;
    final double tertiaryHue = HSLColor.fromColor(colorScheme.tertiary).hue;
    final double harmonyShiftA =
        ((secondaryHue - primaryHue + 540) % 360) - 180;
    final double harmonyShiftB = ((tertiaryHue - primaryHue + 540) % 360) - 180;

    return List.generate(_colorCount, (index) {
      final double harmonyOffset = switch (index % 3) {
        1 => harmonyShiftA * 0.22,
        2 => harmonyShiftB * 0.22,
        _ => 0.0,
      };
      final double hue =
          (primaryHue + index * _goldenAngle + harmonyOffset) % 360;
      final double saturationBase = isDark ? 0.50 : 0.60;
      final double saturation = (saturationBase + (index % 4) * 0.05)
          .clamp(0.48, 0.80)
          .toDouble();
      final List<double> lightnessPattern = isDark
          ? const [0.22, 0.26, 0.20, 0.28]
          : const [0.74, 0.68, 0.62, 0.70];
      final double lightness = lightnessPattern[index % 4];

      final base = HSLColor.fromAHSL(1.0, hue, saturation, lightness).toColor();
      return isDark ? Color.lerp(base, colorScheme.surface, 0.10)! : base;
    });
  }

  static List<Color> _buildCourseTextColors(
    List<Color> backgroundColors,
    ColorScheme colorScheme,
  ) {
    return backgroundColors
        .map((backgroundColor) {
          final Brightness brightness = ThemeData.estimateBrightnessForColor(
            backgroundColor,
          );
          if (brightness == Brightness.dark) {
            return Color.lerp(Colors.white, colorScheme.onPrimary, 0.12)!;
          }
          return Color.lerp(Colors.black, colorScheme.onSurface, 0.45)!;
        })
        .toList(growable: false);
  }

  const SchedulePageView({
    super.key,
    required this.pageController,
    required this.onPageChanged,
    required this.weekList,
    required this.weekCache,
    required this.showWeekend,
    required this.onBoundaryMessage,
    required this.currentWeekIndex,
    this.timeInfoList,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final courseColors = _buildCourseColors(
      theme.colorScheme,
      theme.brightness,
    );
    final courseTextColors = _buildCourseTextColors(
      courseColors,
      theme.colorScheme,
    );

    return NotificationListener<OverscrollNotification>(
      onNotification: (notification) {
        if (notification.overscroll < 0) {
          if (currentWeekIndex == 0) {
            onBoundaryMessage("已经是第一周了");
          }
        } else if (notification.overscroll > 0) {
          if (currentWeekIndex == weekList.length - 1) {
            onBoundaryMessage("已经是最后一周了");
          }
        }
        return false;
      },
      child: PageView.builder(
        controller: pageController,
        onPageChanged: onPageChanged,
        itemCount: weekList.length,
        itemBuilder: (context, index) {
          final weekStr = weekList[index];
          final weekNum = int.tryParse(weekStr) ?? 0;
          final data = weekCache[weekNum];

          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }

          return Column(
            children: [
              ScheduleHeader(
                scheduleData: data,
                height: _headerHeight,
                timeColumnWidth: _timeColumnWidth,
                showWeekend: showWeekend,
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ScheduleTimeColumn(
                        width: _timeColumnWidth,
                        sessionHeight: _sessionHeight,
                        timeInfoList: timeInfoList,
                      ),
                      Expanded(
                        child: ScheduleCourseGrid(
                          events: data.eventList ?? [],
                          sessionHeight: _sessionHeight,
                          showWeekend: showWeekend,
                          colors: courseColors,
                          textColors: courseTextColors,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
