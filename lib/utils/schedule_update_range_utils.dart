int maxWeeksAheadForSchedule({
  required List<String>? weekList,
  required String? currentWeek,
}) {
  if (weekList == null || currentWeek == null) return 0;
  if (weekList.length <= 1) return 0;
  final idx = weekList.indexOf(currentWeek);
  if (idx == -1) return 0;
  final remain = weekList.length - idx - 1;
  if (remain <= 0) return 0;
  return remain;
}
