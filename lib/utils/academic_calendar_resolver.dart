import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/schedule_date.dart';

enum AcademicCalendarResolvedKind {
  normal,
  holiday,
  teachingDay,
  missingSource,
}

class AcademicCalendarResolvedEvent {
  const AcademicCalendarResolvedEvent({
    required this.event,
    required this.actualDate,
    required this.sourceDate,
    required this.actualWeekday,
    required this.sourceWeekday,
  });

  final EventItem event;
  final DateTime actualDate;
  final DateTime sourceDate;
  final int actualWeekday;
  final int sourceWeekday;

  bool get isMapped =>
      actualDate.day != sourceDate.day ||
      actualDate.month != sourceDate.month ||
      actualDate.year != sourceDate.year;
}

class AcademicCalendarResolvedDay {
  const AcademicCalendarResolvedDay({
    required this.actualDate,
    required this.kind,
    required this.label,
    required this.scheduleDate,
    required this.sourceSchedule,
    required this.events,
  });

  final DateTime actualDate;
  final AcademicCalendarResolvedKind kind;
  final String label;
  final DateTime? scheduleDate;
  final ScheduleData? sourceSchedule;
  final List<AcademicCalendarResolvedEvent> events;

  bool get isHoliday => kind == AcademicCalendarResolvedKind.holiday;
  bool get isTeachingDay => kind == AcademicCalendarResolvedKind.teachingDay;
  bool get sourceMissing => kind == AcademicCalendarResolvedKind.missingSource;
}

class AcademicCalendarResolver {
  const AcademicCalendarResolver._();

  static AcademicCalendarResolvedDay resolveDay({
    required DateTime actualDate,
    required Iterable<ScheduleData> schedules,
    AcademicCalendarSnapshot? calendar,
    bool includeHolidayEvents = false,
  }) => resolveAcademicCalendarDay(
    actualDate: actualDate,
    schedules: schedules,
    calendar: calendar,
    includeHolidayEvents: includeHolidayEvents,
  );

  static Map<int, DateTime> scheduleDates(ScheduleData schedule) =>
      academicCalendarScheduleDates(schedule);
}

/// Resolves a calendar rule against already-customized, unmodified weekly data.
///
/// A teaching-day rule reads the source week's events directly. It never calls
/// itself for [scheduleDate], so a source date which is also a holiday still
/// supplies its original classes. Holiday events are opt-in because today,
/// widget, and reminder projections must continue to treat holidays as empty.
AcademicCalendarResolvedDay resolveAcademicCalendarDay({
  required DateTime actualDate,
  required Iterable<ScheduleData> schedules,
  AcademicCalendarSnapshot? calendar,
  bool includeHolidayEvents = false,
}) {
  final actual = DateTime(actualDate.year, actualDate.month, actualDate.day);
  final rule = calendar?.dayAt(actual);
  if (rule?.isHoliday == true && !includeHolidayEvents) {
    return AcademicCalendarResolvedDay(
      actualDate: actual,
      kind: AcademicCalendarResolvedKind.holiday,
      label: rule!.label,
      scheduleDate: null,
      sourceSchedule: null,
      events: const [],
    );
  }

  final sourceDate = rule?.scheduleDate ?? actual;
  final source = _findScheduleContaining(schedules, sourceDate);
  if (source == null) {
    return AcademicCalendarResolvedDay(
      actualDate: actual,
      kind: rule?.isHoliday == true
          ? AcademicCalendarResolvedKind.holiday
          : rule == null
          ? AcademicCalendarResolvedKind.normal
          : AcademicCalendarResolvedKind.missingSource,
      label: rule?.label ?? '',
      scheduleDate: sourceDate,
      sourceSchedule: null,
      events: const [],
    );
  }

  final sourceWeekday = sourceDate.weekday;
  final events = (source.eventList ?? const <EventItem>[])
      .where((event) => _weekday(event.weekDay) == sourceWeekday)
      .map(
        (event) => AcademicCalendarResolvedEvent(
          event: event,
          actualDate: actual,
          sourceDate: sourceDate,
          actualWeekday: actual.weekday,
          sourceWeekday: sourceWeekday,
        ),
      )
      .toList(growable: false);
  return AcademicCalendarResolvedDay(
    actualDate: actual,
    kind: rule?.isHoliday == true
        ? AcademicCalendarResolvedKind.holiday
        : rule == null
        ? AcademicCalendarResolvedKind.normal
        : AcademicCalendarResolvedKind.teachingDay,
    label: rule?.label ?? '',
    scheduleDate: sourceDate,
    sourceSchedule: source,
    events: events,
  );
}

ScheduleData? _findScheduleContaining(
  Iterable<ScheduleData> schedules,
  DateTime date,
) {
  final target = DateTime(date.year, date.month, date.day);
  for (final schedule in schedules) {
    final dates = _scheduleDates(schedule);
    if (dates.values.any((value) => _sameDate(value, target))) return schedule;
  }
  return null;
}

Map<int, DateTime> academicCalendarScheduleDates(ScheduleData schedule) =>
    _scheduleDates(schedule);

Map<int, DateTime> _scheduleDates(ScheduleData schedule) {
  final result = <int, DateTime>{};
  final days = schedule.weekDayList ?? const <WeekDayItem>[];
  for (var index = 0; index < days.length; index++) {
    final item = days[index];
    final weekday = _weekday(item.weekDay) ?? index + 1;
    final date = ScheduleDate.tryParseWeekDate(item.weekDate);
    if (weekday >= 1 && weekday <= 7 && date != null) {
      result[weekday] = DateTime(date.year, date.month, date.day);
    }
  }
  return result;
}

int? _weekday(String? raw) {
  final value = (raw ?? '').trim();
  final number = int.tryParse(value);
  if (number != null) return number;
  const names = {
    '一': 1,
    '二': 2,
    '三': 3,
    '四': 4,
    '五': 5,
    '六': 6,
    '日': 7,
    '天': 7,
  };
  for (final entry in names.entries) {
    if (value.endsWith(entry.key)) return entry.value;
  }
  return null;
}

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
