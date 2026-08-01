import 'dart:convert';

import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CourseReminderScheduler {
  static const String _scheduledIdsKey = 'schedule_course_reminder_ids_v1';
  static const String _timeInfoKey = 'schedule_time_info_cache_v1';

  static Future<void> rescheduleForUser(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await _cancelPrevious(prefs);
    final enabled =
        prefs.getBool(ScheduleSettingsManager.remindersEnabledKey) ?? false;
    if (!enabled || userId.trim().isEmpty) return;
    final granted = await LocalNotifications.ensurePermission();
    if (!granted) return;
    if (!await LocalNotifications.canScheduleExactNotifications()) return;

    final defaultMinutes =
        (prefs.getInt(ScheduleSettingsManager.defaultReminderMinutesKey) ?? 10)
            .clamp(0, 120);
    final clocks = _loadClocks(prefs.getString(_timeInfoKey));
    if (clocks.isEmpty) return;

    final schedules = <ScheduleData>[];
    final prefix = 'schedule_${userId}_';
    for (final key in prefs.getKeys().where((key) => key.startsWith(prefix))) {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          schedules.add(ScheduleData.fromJson(decoded.cast<String, dynamic>()));
        }
      } catch (_) {}
    }

    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 60));
    final occurrences = <_ReminderOccurrence>[];
    final seen = <String>{};
    for (final schedule in schedules) {
      final dates = ScheduleCustomizationManager.scheduleDates(schedule);
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
    for (final occurrence in occurrences.take(64)) {
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
