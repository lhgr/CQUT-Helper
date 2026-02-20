class ScheduleWeekChange {
  final String weekNum;
  final List<String> lines;

  const ScheduleWeekChange({required this.weekNum, required this.lines});

  String get brief => lines.isNotEmpty ? lines.first : '课表有更新';
}
