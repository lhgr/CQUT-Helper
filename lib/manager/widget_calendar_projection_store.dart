import 'dart:convert';

import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/academic_calendar_resolver.dart';
import 'package:cqut_helper/utils/widget_calendar_projection.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Rebuilds every widget projection from the same verified, raw term cache.
/// Customization is supplied by the caller to keep this store independent of
/// both ScheduleApi and ScheduleCustomizationManager.
class WidgetCalendarProjectionStore {
  const WidgetCalendarProjectionStore._();

  static Future<void> _pending = Future<void>.value();

  static String? pinnedValue(
    SharedPreferences prefs,
    String userId,
    String name,
  ) {
    final pinned = prefs.getString('schedule_widget_${name}_$userId')?.trim();
    return pinned?.isNotEmpty == true
        ? pinned
        : prefs.getString('schedule_last_${name}_$userId')?.trim();
  }

  static Set<String> projectionWeeks(String? centerWeek) {
    final parsed = int.tryParse(centerWeek ?? '');
    if (parsed == null) {
      return centerWeek == null || centerWeek.isEmpty
          ? const <String>{}
          : <String>{centerWeek};
    }
    return {
      if (parsed > 1) (parsed - 1).toString(),
      parsed.toString(),
      (parsed + 1).toString(),
    };
  }

  static AcademicCalendarSnapshot? readCalendar(
    SharedPreferences prefs,
    String yearTerm,
  ) {
    try {
      final decoded = jsonDecode(
        prefs.getString('academic_calendar_snapshot_v1_$yearTerm') ?? '',
      );
      if (decoded is! Map<String, dynamic>) return null;
      final calendar = AcademicCalendarSnapshot.fromJson(decoded);
      return calendar.yearTerm == yearTerm ? calendar : null;
    } catch (_) {
      return null;
    }
  }

  static bool containsCalendarSource(
    ScheduleData schedule,
    AcademicCalendarSnapshot? calendar,
  ) {
    final sourceDates = _sourceDates(calendar);
    return academicCalendarScheduleDates(schedule).values
        .any((date) => sourceDates.contains(academicCalendarDateKey(date)));
  }

  static Set<String> _sourceDates(AcademicCalendarSnapshot? calendar) => {
    for (final day in calendar?.days ?? const <AcademicCalendarDay>[])
      if (day.isTeachingDay && day.scheduleDate != null)
        academicCalendarDateKey(day.scheduleDate!),
  };

  static Future<bool> rebuild({
    required SharedPreferences prefs,
    required String userId,
    required String yearTerm,
    required String centerWeek,
    required Future<List<ScheduleData>> Function(
      Iterable<ScheduleData> schedules,
    )
    customizeSchedules,
    AcademicCalendarSnapshot? calendar,
  }) {
    final result = _pending.then(
      (_) => _rebuild(
        prefs: prefs,
        userId: userId,
        yearTerm: yearTerm,
        centerWeek: centerWeek,
        customizeSchedules: customizeSchedules,
        calendar: calendar,
      ),
    );
    _pending = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static Future<bool> _rebuild({
    required SharedPreferences prefs,
    required String userId,
    required String yearTerm,
    required String centerWeek,
    required Future<List<ScheduleData>> Function(
      Iterable<ScheduleData> schedules,
    )
    customizeSchedules,
    AcademicCalendarSnapshot? calendar,
  }) async {
    bool isCurrent() =>
        userId.isNotEmpty &&
        yearTerm.isNotEmpty &&
        (prefs.getString('account') ?? '').trim() == userId &&
        pinnedValue(prefs, userId, 'term') == yearTerm &&
        pinnedValue(prefs, userId, 'week') == centerWeek;
    if (!isCurrent()) return false;
    // Queued rebuilds always prefer the latest persisted calendar revision.
    final resolvedCalendar = readCalendar(prefs, yearTerm) ?? calendar;
    if (resolvedCalendar != null && resolvedCalendar.yearTerm != yearTerm) {
      return false;
    }
    final visibleWeeks = projectionWeeks(centerWeek);
    final sources = _sourceDates(resolvedCalendar);
    final selected = <String, ScheduleData>{};
    final entries = await ScheduleCacheDatabase.instance.loadAllForUser(
      userId,
      yearTerm: yearTerm,
    );
    for (final entry in entries) {
      try {
        final decoded = jsonDecode(entry.rawJson);
        if (decoded is! Map<String, dynamic>) continue;
        final schedule = ScheduleData.fromJson(decoded);
        if (visibleWeeks.contains(entry.weekNum) ||
            academicCalendarScheduleDates(schedule).values.any(
              (date) => sources.contains(academicCalendarDateKey(date)),
            )) {
          selected[entry.weekNum] = schedule;
        }
      } catch (_) {
        // Other verified weeks can still provide the visible projection.
        continue;
      }
    }
    final weeks = selected.keys.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a == centerWeek) return -1;
        if (b == centerWeek) return 1;
        return (int.tryParse(a) ?? 0).compareTo(int.tryParse(b) ?? 0);
      });
    final schedules = await customizeSchedules([
      for (final week in weeks) selected[week]!,
    ]);
    final projection = WidgetCalendarProjection.build(
      yearTerm: yearTerm,
      schedules: schedules,
      calendar: resolvedCalendar,
    );
    if (!isCurrent()) return false;
    final key = 'schedule_widget_calendar_projection_v1_$userId';
    if (WidgetCalendarProjection.hasSameContent(
      prefs.getString(key),
      projection,
    )) {
      return false;
    }
    await prefs.setString(key, jsonEncode(projection));
    return true;
  }
}
