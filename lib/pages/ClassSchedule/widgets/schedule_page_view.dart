import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_course_grid.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_header.dart';
import 'package:cqut/pages/ClassSchedule/widgets/schedule_time_column.dart';
import 'package:cqut/theme/schedule_course_card_theme.dart';
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
    final cardTheme =
        Theme.of(context).extension<ScheduleCourseCardTheme>() ??
        (Theme.of(context).brightness == Brightness.dark
            ? ScheduleCourseCardTheme.dark()
            : ScheduleCourseCardTheme.light());

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
                          yearTerm: data.yearTerm ?? '',
                          sessionHeight: _sessionHeight,
                          showWeekend: showWeekend,
                          backgroundColors: cardTheme.backgrounds,
                          borderColors: cardTheme.borders,
                          titleColors: cardTheme.titleColors,
                          descriptionColors: cardTheme.descriptionColors,
                          buttonColors: cardTheme.buttonColors,
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
