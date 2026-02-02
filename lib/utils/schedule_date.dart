import '../model/schedule_model.dart';

typedef DateRange = ({DateTime start, DateTime end});

class ScheduleDate {
  static DateTime? tryParseWeekDate(
    String? input, {
    DateTime? reference,
  }) {
    if (input == null) return null;
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final normalized = raw.replaceAll('/', '-').replaceAll('.', '-');

    final iso = DateTime.tryParse(normalized);
    if (iso != null) return DateTime(iso.year, iso.month, iso.day);

    final mmDd = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(normalized);
    if (mmDd == null) return null;

    final month = int.tryParse(mmDd.group(1)!) ?? 0;
    final day = int.tryParse(mmDd.group(2)!) ?? 0;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;

    final ref = reference ?? DateTime.now();
    final candidate = DateTime(ref.year, month, day);

    final diff = candidate.difference(DateTime(ref.year, ref.month, ref.day));
    if (diff.inDays.abs() <= 183) return candidate;

    final adjustedYear = diff.inDays > 0 ? ref.year - 1 : ref.year + 1;
    return DateTime(adjustedYear, month, day);
  }

  static DateRange? tryExtractWeekRange(
    List<WeekDayItem>? weekDayList, {
    DateTime? reference,
  }) {
    if (weekDayList == null || weekDayList.isEmpty) return null;

    DateTime? minDate;
    DateTime? maxDate;

    for (final item in weekDayList) {
      final d = tryParseWeekDate(item.weekDate, reference: reference);
      if (d == null) continue;
      if (minDate == null || d.isBefore(minDate)) minDate = d;
      if (maxDate == null || d.isAfter(maxDate)) maxDate = d;
    }

    if (minDate == null || maxDate == null) return null;
    return (start: minDate, end: maxDate);
  }

  static bool dataCoversDate(ScheduleData data, DateTime date) {
    final dayList = data.weekDayList;
    if (dayList == null || dayList.isEmpty) return false;

    if (dayList.any((d) => d.today == true)) return true;

    final range = tryExtractWeekRange(dayList, reference: date);
    if (range == null) return false;

    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(range.start) && !d.isAfter(range.end);
  }
}

