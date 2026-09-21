import 'dart:convert';

import 'package:flutter/foundation.dart';

enum AcademicCalendarDayKind { holiday, teachingDay }

@immutable
class AcademicCalendarDay {
  const AcademicCalendarDay({
    required this.date,
    required this.kind,
    required this.label,
    this.scheduleDate,
  });

  final DateTime date;
  final AcademicCalendarDayKind kind;
  final String label;
  final DateTime? scheduleDate;

  bool get isHoliday => kind == AcademicCalendarDayKind.holiday;
  bool get isTeachingDay => kind == AcademicCalendarDayKind.teachingDay;

  factory AcademicCalendarDay.fromJson(Map<String, dynamic> json) {
    final date = _parseDate(json['date']);
    if (date == null) throw const FormatException('校历日期无效');
    final kind = (json['kind'] ?? '').toString().trim();
    final isTeaching = kind == 'teaching_day';
    final rawScheduleDate = json['schedule_date'];
    final scheduleDate = _parseDate(rawScheduleDate);
    if (isTeaching && scheduleDate == null) {
      throw const FormatException('调休日期缺少 schedule_date');
    }
    if (!isTeaching && rawScheduleDate != null) {
      throw const FormatException('放假日期不能包含 schedule_date');
    }
    if (!isTeaching && kind != 'holiday') {
      throw const FormatException('未知校历日期类型');
    }
    return AcademicCalendarDay(
      date: date,
      kind: isTeaching
          ? AcademicCalendarDayKind.teachingDay
          : AcademicCalendarDayKind.holiday,
      label: (json['label'] ?? '').toString().trim(),
      scheduleDate: scheduleDate,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': _dateKey(date),
    'kind': isTeachingDay ? 'teaching_day' : 'holiday',
    if (label.isNotEmpty) 'label': label,
    if (scheduleDate != null) 'schedule_date': _dateKey(scheduleDate!),
  };
}

@immutable
class AcademicCalendarSnapshot {
  const AcademicCalendarSnapshot({
    required this.schemaVersion,
    required this.yearTerm,
    required this.revision,
    required this.generatedAt,
    required this.complete,
    required this.days,
  });

  final int schemaVersion;
  final String yearTerm;
  final String revision;
  final DateTime generatedAt;
  final bool complete;
  final List<AcademicCalendarDay> days;

  Map<String, AcademicCalendarDay> get byDate => {
    for (final day in days) _dateKey(day.date): day,
  };

  AcademicCalendarDay? dayAt(DateTime date) => byDate[_dateKey(date)];

  factory AcademicCalendarSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['data'] is Map
        ? (json['data'] as Map).cast<String, dynamic>()
        : json;
    final term = (raw['year_term'] ?? '').toString().trim();
    final revision = (raw['revision'] ?? '').toString().trim();
    final generatedAt = DateTime.tryParse(
      (raw['generated_at'] ?? '').toString(),
    );
    final rawSchemaVersion = raw['schema_version'];
    final rawDays = raw['days'];
    if (term.isEmpty ||
        revision.isEmpty ||
        generatedAt == null ||
        rawDays is! List ||
        rawSchemaVersion is! int ||
        rawSchemaVersion != 1) {
      throw const FormatException('校历快照格式无效');
    }
    final days = <AcademicCalendarDay>[];
    for (final item in rawDays) {
      if (item is! Map) throw const FormatException('校历日期规则格式无效');
      days.add(AcademicCalendarDay.fromJson(item.cast<String, dynamic>()));
    }
    days.sort((a, b) => a.date.compareTo(b.date));
    final snapshot = AcademicCalendarSnapshot(
      schemaVersion: rawSchemaVersion,
      yearTerm: term,
      revision: revision,
      generatedAt: generatedAt.toLocal(),
      complete: raw['term_calendar_complete'] == true,
      days: days,
    );
    if (!snapshot.complete) throw const FormatException('校历快照尚未完成');
    if (snapshot.byDate.length != snapshot.days.length) {
      throw const FormatException('校历快照含重复日期');
    }
    return snapshot;
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'year_term': yearTerm,
    'revision': revision,
    'generated_at': generatedAt.toIso8601String(),
    'term_calendar_complete': complete,
    'days': days.map((day) => day.toJson()).toList(growable: false),
  };

  String encode() => jsonEncode(toJson());
}

DateTime? _parseDate(Object? value) {
  final raw = (value ?? '').toString().trim();
  if (raw.isEmpty) return null;
  final match = RegExp(
    r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$',
  ).firstMatch(raw);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  final result = DateTime(year, month, day);
  return result.year == year && result.month == month && result.day == day
      ? DateTime(year, month, day)
      : null;
}

String academicCalendarDateKey(DateTime date) => _dateKey(date);

String _dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
