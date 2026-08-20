import 'dart:convert';

import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
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

  static Future<void> rescheduleForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await _cancelPrevious(prefs);
    final enabled =
        prefs.getBool(ScheduleSettingsManager.remindersEnabledKey) ?? false;
    if (!enabled || userId.trim().isEmpty) {
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
    if (!granted) {
      await _saveStatus(
        prefs,
        CourseReminderStatus(
          enabled: true,
          ready: false,
          reason: '通知权限未授予',
          updatedAt: DateTime.now(),
        ),
      );
      return;
    }
    if (!await LocalNotifications.canScheduleExactNotifications()) {
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
            .clamp(0, 120);
    final clocks = _loadClocks(prefs.getString(_timeInfoKey));
    if (clocks.isEmpty) {
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

    final schedules = <ScheduleData>[];
    final entries = await ScheduleCacheDatabase.instance.loadAllForUser(userId);
    for (final entry in entries) {
      try {
        final decoded = jsonDecode(entry.rawJson);
        if (decoded is Map) {
          final rawSchedule = ScheduleData.fromJson(
            decoded.cast<String, dynamic>(),
          );
          schedules.add(
            await ScheduleCustomizationManager.instance.applyToSchedule(
              userId: userId,
              schedule: rawSchedule,
            ),
          );
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 60));
    final occurrences = <_ReminderOccurrence>[];
    final seen = <String>{};
    final activeScheduleKeys = <String>{};
    var expectedWeekCount = 0;
    DateTime? latestCoveredDate;
    for (final schedule in schedules) {
      final dates = ScheduleCustomizationManager.scheduleDates(schedule);
      final relevantDates = dates.values.where(
        (date) =>
            !date.isBefore(now.subtract(const Duration(days: 7))) &&
            !date.isAfter(horizon),
      );
      if (relevantDates.isNotEmpty) {
        activeScheduleKeys.add(
          '${(schedule.yearTerm ?? '').trim()}|${(schedule.weekNum ?? '').trim()}',
        );
        final termWeeks = schedule.weekList?.length ?? 0;
        final week = int.tryParse((schedule.weekNum ?? '').trim()) ?? 0;
        final weeksNeeded = termWeeks > 0 && week > 0
            ? (termWeeks - week + 1).clamp(0, 10)
            : 0;
        if (weeksNeeded > expectedWeekCount) {
          expectedWeekCount = weeksNeeded;
        }
        for (final date in relevantDates) {
          if (latestCoveredDate == null || date.isAfter(latestCoveredDate)) {
            latestCoveredDate = date;
          }
        }
      }
      for (final event in schedule.eventList ?? const <EventItem>[]) {
        final weekday = int.tryParse((event.weekDay ?? '').trim());
        final date = weekday == null ? null : dates[weekday];
        if (date == null) continue;
        final startSession = _eventStart(event);
        final startMinute = clocks[startSession]?.start;
        if (startMinute == null) continue;
        final reminderMinutes = event.reminderMinutes ?? defaultMinutes;
        if (reminderMinutes <= 0) continue;
        final startAt = DateTime(
          date.year,
          date.month,
          date.day,
          startMinute ~/ 60,
          startMinute % 60,
        );
        final notifyAt = startAt.subtract(Duration(minutes: reminderMinutes));
        if (!notifyAt.isAfter(now) || notifyAt.isAfter(horizon)) continue;
        final name = (event.eventName ?? '').trim().isEmpty
            ? '课程'
            : event.eventName!.trim();
        final identity =
            '${event.eventID}|$name|${date.toIso8601String()}|$startSession';
        if (!seen.add(identity)) continue;
        occurrences.add(
          _ReminderOccurrence(
            id: _positiveId(identity),
            notifyAt: notifyAt,
            title: '$reminderMinutes 分钟后上课',
            body: [
              name,
              if ((event.address ?? '').trim().isNotEmpty)
                event.address!.trim(),
            ].join(' · '),
            payload: 'course_reminder|${event.eventID ?? ''}|$name',
          ),
        );
      }
    }
    occurrences.sort((a, b) => a.notifyAt.compareTo(b.notifyAt));
    final scheduledIds = <int>[];
    // Android is the only supported platform. Do not silently truncate at 64:
    // a dense 60-day timetable can exceed that number and would otherwise
    // miss later reminders without telling the user.
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
    await prefs.setString(_scheduledIdsKey, jsonEncode(scheduledIds));
    final coverageComplete =
        expectedWeekCount == 0 ||
        activeScheduleKeys.length >= expectedWeekCount;
    await _saveStatus(
      prefs,
      CourseReminderStatus(
        enabled: true,
        ready: coverageComplete,
        reason: !coverageComplete
            ? '课表覆盖不完整，打开课表并联网后会继续补齐'
            : occurrences.isEmpty
            ? '未来 60 天没有需要提醒的课程'
            : '提醒计划正常',
        scheduledCount: scheduledIds.length,
        cachedWeekCount: activeScheduleKeys.length,
        expectedWeekCount: expectedWeekCount,
        nextReminderAt: occurrences.isEmpty ? null : occurrences.first.notifyAt,
        coveredUntil: latestCoveredDate,
        updatedAt: DateTime.now(),
      ),
    );
  }

  static Future<void> cancelAll() async {
    final prefs = await SharedPreferences.getInstance();
    await _cancelPrevious(prefs);
  }

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
      } catch (_) {}
    }
    await prefs.remove(_scheduledIdsKey);
  }

  static Future<void> _saveStatus(
    SharedPreferences prefs,
    CourseReminderStatus status,
  ) {
    return prefs.setString(_statusKey, jsonEncode(status.toJson()));
  }

  static Map<int, ({int start, int end})> _loadClocks(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final items = decoded['items'];
      if (items is! List) return const {};
      final result = <int, ({int start, int end})>{};
      for (final item in items) {
        if (item is! Map) continue;
        final session = (item['sessionNum'] as num?)?.toInt();
        final start = _minute(item['startTime']?.toString());
        final end = _minute(item['endTime']?.toString());
        if (session != null && start != null && end != null) {
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

class _ReminderOccurrence {
  final int id;
  final DateTime notifyAt;
  final String title;
  final String body;
  final String payload;

  const _ReminderOccurrence({
    required this.id,
    required this.notifyAt,
    required this.title,
    required this.body,
    required this.payload,
  });
}
