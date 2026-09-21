import 'dart:convert';

import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/academic_calendar_resolver.dart';

/// The compact, already-resolved schedule representation consumed by Android
/// widgets. Native code must not apply academic-calendar rules itself: this
/// projection keeps the Flutter resolver as the single source of truth.
class WidgetCalendarProjection {
  const WidgetCalendarProjection._();

  static const int schemaVersion = 1;

  static Map<String, dynamic> build({
    required String yearTerm,
    required Iterable<ScheduleData> schedules,
    AcademicCalendarSnapshot? calendar,
    DateTime? generatedAt,
  }) {
    final scheduleList = schedules.toList(growable: false);
    final dates = <String, DateTime>{};
    for (final schedule in scheduleList) {
      for (final date in academicCalendarScheduleDates(schedule).values) {
        dates[academicCalendarDateKey(date)] = date;
      }
    }
    for (final day in calendar?.days ?? const <AcademicCalendarDay>[]) {
      dates[academicCalendarDateKey(day.date)] = day.date;
    }

    final resolvedDays = dates.values.toList(growable: false)
      ..sort((a, b) => a.compareTo(b));
    return <String, dynamic>{
      'schema_version': schemaVersion,
      'year_term': yearTerm.trim(),
      'revision': calendar?.revision ?? '',
      'generated_at': (generatedAt ?? DateTime.now()).toIso8601String(),
      'days': [
        for (final date in resolvedDays)
          _resolvedDayToJson(
            resolveAcademicCalendarDay(
              actualDate: date,
              schedules: scheduleList,
              calendar: calendar,
            ),
          ),
      ],
    };
  }

  static String encode({
    required String yearTerm,
    required Iterable<ScheduleData> schedules,
    AcademicCalendarSnapshot? calendar,
    DateTime? generatedAt,
  }) => jsonEncode(
    build(
      yearTerm: yearTerm,
      schedules: schedules,
      calendar: calendar,
      generatedAt: generatedAt,
    ),
  );

  static Map<String, dynamic> _resolvedDayToJson(
    AcademicCalendarResolvedDay day,
  ) => <String, dynamic>{
    'date': academicCalendarDateKey(day.actualDate),
    'kind': switch (day.kind) {
      AcademicCalendarResolvedKind.normal => 'normal',
      AcademicCalendarResolvedKind.holiday => 'holiday',
      AcademicCalendarResolvedKind.teachingDay => 'teaching_day',
      AcademicCalendarResolvedKind.missingSource => 'missing_source',
    },
    if (day.label.isNotEmpty) 'label': day.label,
    if (day.scheduleDate != null)
      'source_date': academicCalendarDateKey(day.scheduleDate!),
    if (day.sourceSchedule?.weekNum?.trim().isNotEmpty == true)
      'source_week_num': day.sourceSchedule!.weekNum!.trim(),
    'events': [
      for (final resolved in day.events)
        <String, dynamic>{
          ...resolved.event.toJson(),
          'actualDate': academicCalendarDateKey(resolved.actualDate),
          'sourceDate': academicCalendarDateKey(resolved.sourceDate),
        },
    ],
  };
}
