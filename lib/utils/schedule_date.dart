import 'package:cqut_helper/model/class_schedule_model.dart';

typedef DateRange = ({DateTime start, DateTime end});

class ScheduleDate {
  static DateTime? tryParseWeekDate(String? input, {DateTime? reference}) {
    if (input == null) return null;
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final normalized = raw.replaceAll('/', '-').replaceAll('.', '-');
    final fullDate = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})$',
    ).firstMatch(normalized);
    final monthDay = RegExp(r'^(\d{1,2})-(\d{1,2})$').firstMatch(normalized);
    final year = int.tryParse(fullDate?.group(1) ?? '');
    final month = int.tryParse(fullDate?.group(2) ?? monthDay?.group(1) ?? '');
    final day = int.tryParse(fullDate?.group(3) ?? monthDay?.group(2) ?? '');
    if (month == null || day == null) return null;
    if (year != null) return _strictDate(year, month, day);
    // Match the native parser: validate a yearless month/day against a leap
    // year first, then resolve it around the supplied reference date.
    if (_strictDate(2000, month, day) == null) return null;

    final ref = reference ?? DateTime.now();
    final candidate = _strictDate(ref.year, month, day);
    if (candidate == null) return null;

    final diff = candidate.difference(DateTime(ref.year, ref.month, ref.day));
    if (diff.inDays.abs() <= 183) return candidate;

    final adjustedYear = diff.inDays > 0 ? ref.year - 1 : ref.year + 1;
    return _strictDate(adjustedYear, month, day);
  }

  static DateTime? _strictDate(int year, int month, int day) {
    if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1) {
      return null;
    }
    final value = DateTime(year, month, day);
    if (value.year != year || value.month != month || value.day != day) {
      return null;
    }
    return value;
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

    final range = tryExtractWeekRange(dayList, reference: date);
    if (range == null) return false;

    final d = DateTime(date.year, date.month, date.day);
    return !d.isBefore(range.start) && !d.isAfter(range.end);
  }
}
