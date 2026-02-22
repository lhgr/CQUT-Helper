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

  static const double _headerHeight = 50.0;
  static const double _timeColumnWidth = 30.0;
  static const double _sessionHeight = 60.0;

  static const List<Color> _lightColors = [
    Color(0xFFA8D8FF),
    Color(0xFFB9FBC0),
    Color(0xFFFFE29A),
    Color(0xFFFFC6FF),
    Color(0xFFFFADAD),
    Color(0xFF9BF6FF),
    Color(0xFFCAFFBF),
    Color(0xFFBDB2FF),
  ];

  static const List<Color> _lightTextColors = [
    Color(0xFF0B3D91),
    Color(0xFF0F5132),
    Color(0xFF7A4E00),
    Color(0xFF5A189A),
    Color(0xFF7B2C2C),
    Color(0xFF006064),
    Color(0xFF155724),
    Color(0xFF2D1E8F),
  ];

  static final List<Color> _darkColors = [
    Colors.blue.shade900,
    Colors.green.shade900,
    Colors.orange.shade900,
    Colors.purple.shade900,
    Colors.red.shade900,
    Colors.teal.shade900,
    Colors.pink.shade900,
    Colors.indigo.shade900,
  ];

  static final List<Color> _darkTextColors = [
    Colors.blue.shade300,
    Colors.green.shade300,
    Colors.orange.shade300,
    Colors.purple.shade300,
    Colors.red.shade300,
    Colors.teal.shade300,
    Colors.pink.shade300,
    Colors.indigo.shade300,
  ];

  const SchedulePageView({
    super.key,
    required this.pageController,
    required this.onPageChanged,
    required this.weekList,
    required this.weekCache,
    required this.showWeekend,
    required this.onBoundaryMessage,
    required this.currentWeekIndex,
  });

  @override
  Widget build(BuildContext context) {
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
                      ),
                      Expanded(
                        child: ScheduleCourseGrid(
                          events: data.eventList ?? [],
                          sessionHeight: _sessionHeight,
                          showWeekend: showWeekend,
                          colors:
                              Theme.of(context).brightness == Brightness.dark
                                  ? _darkColors
                                  : _lightColors,
                          textColors:
                              Theme.of(context).brightness == Brightness.dark
                                  ? _darkTextColors
                                  : _lightTextColors,
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
