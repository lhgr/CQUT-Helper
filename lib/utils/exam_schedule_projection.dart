import 'dart:math' as math;

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/utils/schedule_date.dart';

class ExamProjection {
  const ExamProjection(this.exam, this.weekday, this.top, this.height);
  final ExamRecord exam;
  final int weekday;
  final double top;
  final double height;
}

class ExamTimeAxis {
  ExamTimeAxis._(this.sessions, this.sessionHeight);
  final List<({int start, int end})> sessions;
  final double sessionHeight;
  double get height => sessions.length * sessionHeight;

  static ExamTimeAxis? tryCreate(
    List<CampusTimeInfo>? items, {
    required double sessionHeight,
    int sessionCount = 10,
  }) {
    if (items == null || sessionHeight <= 0) return null;
    int? clock(String? text) {
      final match = RegExp(r'^(\d{1,2})[:：](\d{2})(?::\d{2})?$')
          .firstMatch(text?.trim() ?? '');
      if (match == null) return null;
      final h = int.parse(match[1]!), m = int.parse(match[2]!);
      return h < 24 && m < 60 ? h * 60 + m : null;
    }

    final sessions = <({int start, int end})>[];
    for (var number = 1; number <= sessionCount; number++) {
      final matches = items.where((item) => item.sessionNum == number).toList();
      if (matches.length != 1) return null;
      final start = clock(matches.single.startTime),
          end = clock(matches.single.endTime);
      if (start == null ||
          end == null ||
          end <= start ||
          (sessions.isNotEmpty && start < sessions.last.end)) {
        return null;
      }
      sessions.add((start: start, end: end));
    }
    return ExamTimeAxis._(sessions, sessionHeight);
  }

  double position(int minute) {
    for (var i = 0; i < sessions.length; i++) {
      final session = sessions[i];
      if (minute <= session.start) return i * sessionHeight;
      if (minute < session.end) {
        return (i + (minute - session.start) / (session.end - session.start)) *
            sessionHeight;
      }
    }
    return height;
  }

  ExamProjection project(ExamRecord exam, int weekday) {
    final start = exam.schoolStartAt!, end = exam.schoolEndAt!;
    final top = position(start.hour * 60 + start.minute);
    final bottom = position(end.hour * 60 + end.minute);
    final size = math.min(height, math.max(32.0, bottom - top));
    final expandedTop = ((top + bottom - size) / 2).clamp(0.0, height - size);
    return ExamProjection(exam, weekday, expandedTop, size);
  }
}

/// Resolves actual calendar dates, independently of teaching-day remapping.
/// Yearless dates use an explicit date in the week or the selected academic
/// term, so browsing another term never depends on the device's current year.
DateTime? scheduleExamWeekStart(ScheduleData data) {
  final items = data.weekDayList ?? const <WeekDayItem>[];
  DateTime? reference;
  for (final item in items) {
    final raw = (item.weekDate ?? '').trim();
    if (RegExp(r'^\d{4}[-/.]\d{1,2}[-/.]\d{1,2}$').hasMatch(raw)) {
      reference = ScheduleDate.tryParseWeekDate(raw);
      if (reference != null) break;
    }
  }
  if (reference == null) {
    final term = RegExp(r'^(\d{4})-(\d{4})-([12])$')
        .firstMatch((data.yearTerm ?? '').trim());
    if (term == null) return null;
    final startYear = int.parse(term[1]!), endYear = int.parse(term[2]!);
    if (endYear != startYear + 1) return null;
    // Midpoints of the autumn/winter and spring/summer semesters keep the
    // existing nearest-year parser stable, including December/January weeks.
    reference = term[3] == '1'
        ? DateTime(startYear, 12, 1)
        : DateTime(endYear, 6, 1);
  }
  final days = <DateTime>[];
  for (final item in items) {
    final date = ScheduleDate.tryParseWeekDate(
      item.weekDate,
      reference: reference,
    );
    if (date != null) days.add(DateTime.utc(date.year, date.month, date.day));
  }
  if (days.isEmpty) return null;
  final monday = days.first.subtract(Duration(days: days.first.weekday - 1));
  if (days.any(
    (day) =>
        day.difference(monday).inDays < 0 || day.difference(monday).inDays > 6,
  )) {
    return null;
  }
  return monday;
}

List<ExamRecord> examsInScheduleWeek(
  ScheduleData data,
  List<ExamRecord> exams,
) {
  final monday = scheduleExamWeekStart(data);
  if (monday == null) return const [];
  return exams
      .where((exam) {
        if (!exam.hasValidTime) return false;
        final start = exam.schoolStartAt!, end = exam.schoolEndAt!;
        if (start.year != end.year ||
            start.month != end.month ||
            start.day != end.day) {
          return false;
        }
        final date = DateTime.utc(start.year, start.month, start.day);
        return date.difference(monday).inDays >= 0 &&
            date.difference(monday).inDays < 7;
      })
      .toList(growable: false);
}

class ScheduleLaneItem {
  const ScheduleLaneItem(this.key, this.weekday, this.top, this.bottom);
  final Object key;
  final int weekday;
  final double top, bottom;
}

typedef ScheduleLane = ({int index, int count});

/// Interval components share equal-width lanes, using final visual bounds.
Map<Object, ScheduleLane> assignScheduleLanes(List<ScheduleLaneItem> items) {
  final result = <Object, ScheduleLane>{};
  for (var day = 1; day <= 7; day++) {
    final sorted = items.where((item) => item.weekday == day).toList()
      ..sort(
        (a, b) => a.top != b.top
            ? a.top.compareTo(b.top)
            : b.bottom.compareTo(a.bottom),
      );
    var component = <ScheduleLaneItem>[], componentEnd = -double.infinity;
    void flush() {
      final ends = <double>[];
      final assigned = <Object, int>{};
      for (final item in component) {
        var lane = ends.indexWhere((end) => end <= item.top);
        if (lane < 0) {
          lane = ends.length;
          ends.add(item.bottom);
        } else {
          ends[lane] = item.bottom;
        }
        assigned[item.key] = lane;
      }
      for (final entry in assigned.entries) {
        result[entry.key] = (index: entry.value, count: ends.length);
      }
    }

    for (final item in sorted) {
      if (component.isNotEmpty && item.top >= componentEnd) {
        flush();
        component = [];
        componentEnd = -double.infinity;
      }
      component.add(item);
      componentEnd = math.max(componentEnd, item.bottom);
    }
    flush();
  }
  return result;
}
