import 'dart:convert';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/course_reminder_mode.dart';

import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/academic_calendar_resolver.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CourseReminderScheduler {
  static const String _scheduledIdsKey = 'schedule_course_reminder_ids_v1';
  static const String _timeInfoKey = 'schedule_time_info_cache_v1';
  static const String _statusKey = 'schedule_course_reminder_status_v1';

  static Future<CourseReminderStatus> loadStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_statusKey);
    if (raw == null || raw.isEmpty) return const CourseReminderStatus.empty();
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return CourseReminderStatus.fromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
    return const CourseReminderStatus.empty();
  }

  static Future<void>? _pending;
  static Future<void> _serialize(Future<void> Function() action) {
    final previous = _pending;
    final result = previous == null
        ? Future<void>.microtask(action)
        : previous.then((_) => action());
    late final Future<void> tail;
    void release() {
      if (identical(_pending, tail)) _pending = null;
    }

    tail = result.then<void>(
      (_) => release(),
      onError: (Object error, StackTrace stack) => release(),
    );
    _pending = tail;
    return result;
  }

  static Future<void> rescheduleForUser(
    String userId, {
    AcademicCalendarSnapshot? calendar,
  }) => _serialize(() async {
    try {
      await _rescheduleForUser(userId, calendar: calendar);
    } catch (error, stackTrace) {
      AppLogger.I.error(
        'CourseReminderScheduler',
        'reminder rebuild failed',
        error: error,
        stackTrace: stackTrace,
        fields: {
          'hasAccount': userId.trim().isNotEmpty,
          'hasProvidedCalendar': calendar != null,
        },
      );
      await CourseReminderMode.cancelAndRestore();
      rethrow;
    }
  });
  static Future<void> _rescheduleForUser(
    String userId, {
    AcademicCalendarSnapshot? calendar,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _cancelPrevious(prefs);
    final enabled =
        prefs.getBool(ScheduleSettingsManager.remindersEnabledKey) ?? false;
    if (!enabled || userId.trim().isEmpty) {
      await CourseReminderMode.cancelAndRestore();
      await _saveStatus(
        prefs,
        CourseReminderStatus(
          enabled: enabled,
          ready: false,
          reason: enabled ? '未找到当前账号' : '课前提醒已关闭',
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }
    // Rescheduling can run in a headless WorkManager isolate, where there is no
    // Activity from which Android can display a permission dialog. Permission
    // requests belong to the settings UI; background work only checks the
    // permission that has already been granted.
    final granted = await LocalNotifications.areNotificationsEnabled();
    if (!await LocalNotifications.canScheduleExactNotifications()) {
      await CourseReminderMode.cancelAndRestore();
      await _saveStatus(
        prefs,
        CourseReminderStatus(
          enabled: true,
          ready: false,
          reason: '精确闹钟权限未授予',
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }

    final defaultMinutes =
        (prefs.getInt(ScheduleSettingsManager.defaultReminderMinutesKey) ?? 10)
            .clamp(1, 120);
    final clocks = _loadClocks(prefs.getString(_timeInfoKey));
    if (clocks.isEmpty) {
      await CourseReminderMode.cancelAndRestore();
      await _saveStatus(
        prefs,
        CourseReminderStatus(
          enabled: true,
          ready: false,
          reason: '尚未同步学校作息时间',
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }

    final cachedSchedules = <_CachedReminderSchedule>[];
    final entries = await ScheduleCacheDatabase.instance.loadAllForUser(userId);
    for (final entry in entries) {
      try {
        final decoded = jsonDecode(entry.rawJson);
        if (decoded is Map) {
          final rawSchedule = ScheduleData.fromJson(
            decoded.cast<String, dynamic>(),
          );
          cachedSchedules.add(
            _CachedReminderSchedule(
              schedule: rawSchedule,
              fetchedAt: entry.fetchedAt,
            ),
          );
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 60));
    final activeTerm = _selectReminderTerm(
      prefs: prefs,
      userId: userId,
      cachedSchedules: cachedSchedules,
      now: now,
    );
    final effectiveCalendar =
        calendar ??
        loadCachedCalendarForTerm(prefs: prefs, yearTerm: activeTerm);
    final schedules = <ScheduleData>[];
    for (final cached in cachedSchedules) {
      if ((cached.schedule.yearTerm ?? '').trim() != activeTerm) continue;
      schedules.add(
        await ScheduleCustomizationManager.instance.applyToSchedule(
          userId: userId,
          schedule: cached.schedule,
        ),
      );
    }
    final coverage = evaluateCourseReminderCoverage(
      schedules: schedules,
      now: now,
      horizon: horizon,
    );
    final plan = planCourseReminders(
      schedules: schedules,
      calendar: effectiveCalendar,
      clocks: clocks,
      now: now,
      horizon: horizon,
      defaultMinutes: defaultMinutes,
      atStart:
          prefs.getBool(ScheduleSettingsManager.defaultReminderAtStartKey) ??
          false,
    );
    final occurrences = granted
        ? plan.notifications
        : <CourseReminderOccurrence>[];
    final modeName = prefs.getString(ScheduleSettingsManager.courseAutoModeKey);
    final mode = CourseAutoMode.values.firstWhere(
      (mode) => mode.name == modeName,
      orElse: () => CourseAutoMode.off,
    );
    final scheduledIds = <int>[];
    // Android is the only supported platform. Do not silently truncate at 64:
    // a dense 60-day timetable can exceed that number and would otherwise
    // miss later reminders without telling the user.
    try {
      for (final occurrence in occurrences) {
        await LocalNotifications.scheduleCourseReminder(
          id: occurrence.id,
          title: occurrence.title,
          body: occurrence.body,
          scheduledAt: occurrence.notifyAt,
          payload: occurrence.payload,
        );
        scheduledIds.add(occurrence.id);
      }
    } catch (_) {
      await LocalNotifications.cancelIds(scheduledIds);
      rethrow;
    }
    await prefs.setString(_scheduledIdsKey, jsonEncode(scheduledIds));
    if (schedules.isEmpty) {
      await CourseReminderMode.cancelAndRestore();
    } else {
      await CourseReminderMode.replaceSchedule(
        mode: mode,
        intervals: plan.intervals,
      );
    }

    await _saveStatus(
      prefs,
      CourseReminderStatus(
        enabled: true,
        ready: granted && coverage.complete,
        reason: !granted
            ? '通知权限未授予'
            : !coverage.measurable
            ? '尚未缓存可用于提醒的当前学期课表'
            : !coverage.complete
            ? '课表覆盖不完整，请联网后点击重建以补齐'
            : occurrences.isEmpty
            ? '未来 60 天没有需要提醒的课程'
            : '提醒计划正常',
        scheduledCount: scheduledIds.length,
        cachedWeekCount: coverage.cachedWeekCount,
        expectedWeekCount: coverage.expectedWeekCount,
        nextReminderAt: occurrences.isEmpty ? null : occurrences.first.notifyAt,
        coveredUntil: coverage.coveredUntil,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// Reads the immutable published calendar cache without making a network
  /// request. Normal schedule refreshes use this path so a reschedule cannot
  /// silently discard already-published makeup-day rules.
  static AcademicCalendarSnapshot? loadCachedCalendarForTerm({
    required SharedPreferences prefs,
    required String yearTerm,
  }) {
    final term = yearTerm.trim();
    if (term.isEmpty) return null;
    final raw = prefs.getString('academic_calendar_snapshot_v1_$term');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AcademicCalendarSnapshot.fromJson(
          decoded.cast<String, dynamic>(),
        );
      }
    } catch (_) {}
    return null;
  }

  static String _selectReminderTerm({
    required SharedPreferences prefs,
    required String userId,
    required List<_CachedReminderSchedule> cachedSchedules,
    required DateTime now,
  }) {
    if (cachedSchedules.isEmpty) return '';
    final preferredTerms = <String>[
      (prefs.getString('schedule_widget_term_$userId') ?? '').trim(),
      (prefs.getString('schedule_last_term_$userId') ?? '').trim(),
    ];
    for (final term in preferredTerms) {
      if (term.isEmpty) continue;
      if (cachedSchedules.any(
        (cached) => (cached.schedule.yearTerm ?? '').trim() == term,
      )) {
        return term;
      }
    }

    final today = DateTime(now.year, now.month, now.day);
    final coveringToday = cachedSchedules.where((cached) {
      final dates = ScheduleCustomizationManager.scheduleDates(cached.schedule)
          .values;
      if (dates.isEmpty) return false;
      final first = dates.reduce((a, b) => a.isBefore(b) ? a : b);
      final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);
      return !today.isBefore(first) && !today.isAfter(last);
    }).toList();
    if (coveringToday.isNotEmpty) {
      coveringToday.sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
      return (coveringToday.first.schedule.yearTerm ?? '').trim();
    }

    final newest = cachedSchedules.toList()
      ..sort((a, b) => b.fetchedAt.compareTo(a.fetchedAt));
    return (newest.first.schedule.yearTerm ?? '').trim();
  }

  static Future<void> cancelAll() => _serialize(() async {
    await CourseReminderMode.cancelAndRestore();
    final prefs = await SharedPreferences.getInstance();
    await _cancelPrevious(prefs);
  });

  static Future<void> _cancelPrevious(SharedPreferences prefs) async {
    final raw = prefs.getString(_scheduledIdsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          await LocalNotifications.cancelIds(
            decoded.whereType<num>().map((e) => e.toInt()),
          );
        }
      } catch (error, stackTrace) {
        AppLogger.I.error(
          'CourseReminderScheduler',
          'cancel reminders failed',
          error: error,
          stackTrace: stackTrace,
        );
        rethrow;
      }
    }
    await prefs.remove(_scheduledIdsKey);
  }

  static Future<void> _saveStatus(
    SharedPreferences prefs,
    CourseReminderStatus status,
  ) {
    return prefs.setString(_statusKey, jsonEncode(status.toJson()));
  }

  static Map<int, ({int start, int? end})> _loadClocks(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final items = decoded['items'];
      if (items is! List) return const {};
      final result = <int, ({int start, int? end})>{};
      for (final item in items) {
        if (item is! Map) continue;
        final session = (item['sessionNum'] as num?)?.toInt();
        final start = _minute(item['startTime']?.toString());
        final end = _minute(item['endTime']?.toString());
        if (session != null && start != null) {
          result[session] = (start: start, end: end);
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  static int? _minute(String? raw) {
    final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{1,2})').firstMatch(raw ?? '');
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static int _eventStart(EventItem event) {
    final direct = int.tryParse((event.sessionStart ?? '').trim());
    if (direct != null && direct > 0) return direct;
    final values = (event.sessionList ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    return values.isEmpty ? 1 : values.reduce((a, b) => a < b ? a : b);
  }

  static int _positiveId(String value) => value.hashCode & 0x7fffffff;
}

class CourseReminderPlan {
  final List<CourseReminderOccurrence> notifications;
  final List<CourseAutoModeInterval> intervals;
  const CourseReminderPlan({
    required this.notifications,
    required this.intervals,
  });
}

/// School clocks always use China standard time, independently of device zone.
DateTime _schoolTime(DateTime date, int minute) => DateTime.utc(
  date.year,
  date.month,
  date.day,
  minute ~/ 60,
  minute % 60,
).subtract(const Duration(hours: 8));

CourseReminderPlan planCourseReminders({
  required Iterable<ScheduleData> schedules,
  AcademicCalendarSnapshot? calendar,
  required Map<int, ({int start, int? end})> clocks,
  required DateTime now,
  required DateTime horizon,
  required int defaultMinutes,
  required bool atStart,
}) {
  final items = schedules.toList();
  final notifications = <CourseReminderOccurrence>[];
  final intervals = <CourseAutoModeInterval>[];
  final seen = <String>{};
  void add(EventItem event, DateTime date) {
    final session = CourseReminderScheduler._eventStart(event);
    final minute = clocks[session]?.start;
    if (minute == null) return;
    final name = (event.eventName ?? '').trim().isEmpty
        ? '课程'
        : event.eventName!.trim();
    final identity =
        '${event.eventID}|$name|${date.year}-${date.month}-${date.day}|$session';
    if (!seen.add(identity)) return;
    final start = _schoolTime(date, minute);
    final listed = (event.sessionList ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((value) => value > 0)
        .toList();
    final count = int.tryParse((event.sessionLast ?? '').trim());
    final lastSession = count != null && count > 0
        ? session + count - 1
        : (listed.isEmpty ? session : listed.reduce((a, b) => a > b ? a : b));
    final endMinute = clocks[lastSession]?.end;
    if (endMinute != null) {
      final end = _schoolTime(date, endMinute);
      if (end.isAfter(now) && end.isAfter(start) && !start.isAfter(horizon)) {
        intervals.add(
          CourseAutoModeInterval(
            startMillis: start.millisecondsSinceEpoch,
            endMillis: end.millisecondsSinceEpoch,
          ),
        );
      }
    }
    // A per-course positive override always wins over the global at-start flag.
    final override = event.reminderMinutes;
    if (override != null && override <= 0) return;
    final minutes = override == null && atStart
        ? 0
        : (override ?? defaultMinutes).clamp(1, 120);
    final notifyAt = start.subtract(Duration(minutes: minutes));
    if (!notifyAt.isAfter(now) || notifyAt.isAfter(horizon)) return;
    notifications.add(
      CourseReminderOccurrence(
        id: CourseReminderScheduler._positiveId(identity),
        notifyAt: notifyAt,
        title: minutes == 0 ? '上课时间到了' : '$minutes 分钟后上课',
        body: [
          name,
          if ((event.address ?? '').trim().isNotEmpty) event.address!.trim(),
        ].join(' · '),
        payload: 'course_reminder|${event.eventID ?? ''}|$name',
      ),
    );
  }

  if (calendar == null) {
    for (final schedule in items) {
      final dates = ScheduleCustomizationManager.scheduleDates(schedule);
      for (final event in schedule.eventList ?? const <EventItem>[]) {
        final date = dates[int.tryParse((event.weekDay ?? '').trim())];
        if (date != null) add(event, date);
      }
    }
  } else {
    final schoolNow = now.toUtc().add(const Duration(hours: 8));
    final schoolHorizon = horizon.toUtc().add(const Duration(hours: 8));
    for (
      var date = DateTime.utc(schoolNow.year, schoolNow.month, schoolNow.day);
      !date.isAfter(
        DateTime.utc(
          schoolHorizon.year,
          schoolHorizon.month,
          schoolHorizon.day,
        ),
      );
      date = date.add(const Duration(days: 1))
    ) {
      final resolved = resolveAcademicCalendarDay(
        actualDate: date,
        schedules: items,
        calendar: calendar,
      );
      for (final item in resolved.events) {
        add(item.event, date);
      }
    }
  }
  notifications.sort((a, b) => a.notifyAt.compareTo(b.notifyAt));
  intervals.sort((a, b) => a.startMillis.compareTo(b.startMillis));
  final merged = <CourseAutoModeInterval>[];
  for (final interval in intervals) {
    if (merged.isNotEmpty && interval.startMillis <= merged.last.endMillis) {
      final previous = merged.removeLast();
      merged.add(
        CourseAutoModeInterval(
          startMillis: previous.startMillis,
          endMillis: interval.endMillis > previous.endMillis
              ? interval.endMillis
              : previous.endMillis,
        ),
      );
    } else {
      merged.add(interval);
    }
  }
  return CourseReminderPlan(notifications: notifications, intervals: merged);
}

class CourseReminderCoverage {
  final Set<String> expectedWeeks;
  final Set<String> cachedWeeks;
  final DateTime? coveredUntil;
  final bool measurable;

  const CourseReminderCoverage({
    required this.expectedWeeks,
    required this.cachedWeeks,
    required this.coveredUntil,
    required this.measurable,
  });

  int get expectedWeekCount => expectedWeeks.length;
  int get cachedWeekCount => cachedWeeks.length;
  bool get complete => measurable && cachedWeeks.containsAll(expectedWeeks);
}

CourseReminderCoverage evaluateCourseReminderCoverage({
  required Iterable<ScheduleData> schedules,
  required DateTime now,
  required DateTime horizon,
}) {
  final items = schedules.toList(growable: false);
  final today = DateTime(now.year, now.month, now.day);
  final lastDay = DateTime(horizon.year, horizon.month, horizon.day);
  final candidates = <_CoverageAnchor>[];
  for (final schedule in items) {
    final week = int.tryParse((schedule.weekNum ?? '').trim());
    final weekList = schedule.weekList ?? const <String>[];
    final dates = ScheduleCustomizationManager.scheduleDates(schedule).values;
    if (week == null || week <= 0 || weekList.isEmpty || dates.isEmpty) {
      continue;
    }
    final first = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final last = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final distance = today.isBefore(first)
        ? first.difference(today).inDays
        : today.isAfter(last)
        ? today.difference(last).inDays
        : 0;
    candidates.add(
      _CoverageAnchor(
        schedule: schedule,
        week: week,
        firstDate: first,
        lastDate: last,
        distanceFromToday: distance,
      ),
    );
  }
  if (candidates.isEmpty || lastDay.isBefore(today)) {
    return const CourseReminderCoverage(
      expectedWeeks: <String>{},
      cachedWeeks: <String>{},
      coveredUntil: null,
      measurable: false,
    );
  }
  candidates.sort((a, b) => a.distanceFromToday.compareTo(b.distanceFromToday));
  final anchor = candidates.first;
  final expectedWeeks = <String>{};
  for (final rawWeek in anchor.schedule.weekList ?? const <String>[]) {
    final normalizedWeek = rawWeek.trim();
    final week = int.tryParse(normalizedWeek);
    if (week == null || week <= 0) continue;
    final offset = Duration(days: (week - anchor.week) * 7);
    final start = anchor.firstDate.add(offset);
    final end = anchor.lastDate.add(offset);
    if (!end.isBefore(today) && !start.isAfter(lastDay)) {
      expectedWeeks.add(normalizedWeek);
    }
  }

  final cachedWeeks = items
      .map((schedule) => (schedule.weekNum ?? '').trim())
      .where(expectedWeeks.contains)
      .toSet();
  DateTime? coveredUntil;
  for (final schedule in items) {
    final week = (schedule.weekNum ?? '').trim();
    if (!cachedWeeks.contains(week)) continue;
    for (final date in ScheduleCustomizationManager.scheduleDates(
      schedule,
    ).values) {
      if (date.isAfter(lastDay)) continue;
      if (coveredUntil == null || date.isAfter(coveredUntil)) {
        coveredUntil = date;
      }
    }
  }
  return CourseReminderCoverage(
    expectedWeeks: expectedWeeks,
    cachedWeeks: cachedWeeks,
    coveredUntil: coveredUntil,
    measurable: true,
  );
}

class _CoverageAnchor {
  final ScheduleData schedule;
  final int week;
  final DateTime firstDate;
  final DateTime lastDate;
  final int distanceFromToday;

  const _CoverageAnchor({
    required this.schedule,
    required this.week,
    required this.firstDate,
    required this.lastDate,
    required this.distanceFromToday,
  });
}

class _CachedReminderSchedule {
  final ScheduleData schedule;
  final DateTime fetchedAt;

  const _CachedReminderSchedule({
    required this.schedule,
    required this.fetchedAt,
  });
}

class CourseReminderStatus {
  final bool enabled;
  final bool ready;
  final String reason;
  final int scheduledCount;
  final int cachedWeekCount;
  final int expectedWeekCount;
  final DateTime? nextReminderAt;
  final DateTime? coveredUntil;
  final DateTime? updatedAt;

  const CourseReminderStatus({
    required this.enabled,
    required this.ready,
    required this.reason,
    this.scheduledCount = 0,
    this.cachedWeekCount = 0,
    this.expectedWeekCount = 0,
    this.nextReminderAt,
    this.coveredUntil,
    this.updatedAt,
  });

  const CourseReminderStatus.empty()
    : enabled = false,
      ready = false,
      reason = '尚未建立提醒计划',
      scheduledCount = 0,
      cachedWeekCount = 0,
      expectedWeekCount = 0,
      nextReminderAt = null,
      coveredUntil = null,
      updatedAt = null;

  factory CourseReminderStatus.fromJson(Map<String, dynamic> json) {
    DateTime? time(String key) =>
        DateTime.tryParse((json[key] ?? '').toString())?.toLocal();
    return CourseReminderStatus(
      enabled: json['enabled'] == true,
      ready: json['ready'] == true,
      reason: (json['reason'] ?? '尚未建立提醒计划').toString(),
      scheduledCount: (json['scheduledCount'] as num?)?.toInt() ?? 0,
      cachedWeekCount: (json['cachedWeekCount'] as num?)?.toInt() ?? 0,
      expectedWeekCount: (json['expectedWeekCount'] as num?)?.toInt() ?? 0,
      nextReminderAt: time('nextReminderAt'),
      coveredUntil: time('coveredUntil'),
      updatedAt: time('updatedAt'),
    );
  }

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'ready': ready,
    'reason': reason,
    'scheduledCount': scheduledCount,
    'cachedWeekCount': cachedWeekCount,
    'expectedWeekCount': expectedWeekCount,
    'nextReminderAt': nextReminderAt?.toIso8601String(),
    'coveredUntil': coveredUntil?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
  };
}

class CourseReminderOccurrence {
  final int id;
  final DateTime notifyAt;
  final String title;
  final String body;
  final String payload;

  const CourseReminderOccurrence({
    required this.id,
    required this.notifyAt,
    required this.title,
    required this.body,
    required this.payload,
  });
}
