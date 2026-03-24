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

  static const List<Color> _courseColors = [
    Color(0xFFE6F4FF),
    Color(0xFFFDEBDD),
    Color(0xFFDEFBF7),
    Color(0xFFEEEDFF),
    Color(0xFFFCEBCD),
    Color(0xFFFFEFF0),
    Color(0xFFFFEEF8),
    Color(0xFFE2F9F3),
    Color(0xFFFFF9C9),
    Color(0xFFFAEDFF),
    Color(0xFFF4F2FD),
  ];

  static const List<Color> _courseDarkerColors = [
    Color(0xFF00A8FF),
    Color(0xFFFF7F50),
    Color(0xFF00CEC9),
    Color(0xFFA55EEA),
    Color(0xFFFFB142),
    Color(0xFFFF4757),
    Color(0xFFFF6B81),
    Color(0xFF00D2D3),
    Color(0xFFFFDD59),
    Color(0xFFCD84F1),
    Color(0xFF7D5FFF),
  ];

  static List<Color> _buildCourseColors() {
    return _courseColors;
  }

  static List<Color> _buildCourseTextColors() {
    return _courseDarkerColors;
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
    final courseColors = _buildCourseColors();
    final courseTextColors = _buildCourseTextColors();

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
