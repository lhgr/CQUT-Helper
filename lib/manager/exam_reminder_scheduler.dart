import 'dart:convert';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Schedules and cancels per-exam advance-notice reminders.
///
/// Each exam gets one notification fired [defaultReminderMinutes] before
/// [ExamRecord.startAt]. Reminders share the same enabled flag as course
/// reminders ([ScheduleSettingsManager.remindersEnabledKey]).
class ExamReminderScheduler {
  static const String _scheduledIdsKey = 'exam_reminder_scheduled_ids_v1';

  // Exam reminder IDs are offset from course reminder IDs to avoid collisions.
  // Course reminders use hash-based IDs; we reserve the top of the int32 range.
  static const int _idBase = 0x60000000;

  /// Stable notification ID for [examKey] so a rescheduled exam replaces the
  /// same slot rather than accumulating duplicates.
  static int _idForKey(String examKey) {
    var hash = 0;
    for (final unit in examKey.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return (_idBase + hash) & 0x7fffffff;
  }

  /// Rebuilds exam reminders for [userId].
  ///
  /// Cancels all previously scheduled exam reminders for this user, then
  /// schedules one notification per upcoming exam that has a valid start time.
  /// Does nothing when reminders are disabled or notifications are unavailable.
  static Future<void> rescheduleForUser(
    String userId, {
    List<ExamRecord>? exams,
    Future<SharedPreferences> Function()? prefsProvider,
  }) async {
    final getPrefs = prefsProvider ?? SharedPreferences.getInstance;
    final prefs = await getPrefs();
    final enabled =
        prefs.getBool(ScheduleSettingsManager.remindersEnabledKey) ?? false;
    if (!enabled) {
      await _cancelPrevious(prefs);
      return;
    }
    if (!LocalNotifications.isSupported) {
      await _cancelPrevious(prefs);
      return;
    }
    final granted = await LocalNotifications.areNotificationsEnabled();
    if (!granted) {
      await _cancelPrevious(prefs);
      return;
    }
    if (LocalNotifications.requiresExactAlarms &&
        !await LocalNotifications.canScheduleExactNotifications()) {
      await _cancelPrevious(prefs);
      return;
    }

    final defaultMinutes =
        (prefs.getInt(ScheduleSettingsManager.defaultReminderMinutesKey) ?? 10)
            .clamp(1, 120);
    final now = DateTime.now();
    final horizon = now.add(const Duration(days: 60));

    final upcoming = (exams ?? const <ExamRecord>[])
        .where(
          (exam) =>
              exam.startAt != null &&
              exam.startAt!.isAfter(now) &&
              exam.startAt!.isBefore(horizon),
        )
        .toList();

    final newIds = <int>[];
    await _cancelPrevious(prefs);

    for (final exam in upcoming) {
      final notifyAt = exam.startAt!.subtract(
        Duration(minutes: defaultMinutes),
      );
      if (!notifyAt.isAfter(now)) continue;
      final id = _idForKey(exam.key);
      final location = exam.location;
      final body = location.isNotEmpty
          ? '距开考还有 $defaultMinutes 分钟 · $location'
          : '距开考还有 $defaultMinutes 分钟';
      try {
        final scheduled = await LocalNotifications.scheduleCourseReminder(
          id: id,
          title: exam.courseName,
          body: body,
          scheduledAt: notifyAt,
          payload: 'exam_reminder|${exam.key}',
        );
        if (scheduled) newIds.add(id);
      } catch (error, stackTrace) {
        AppLogger.I.warn(
          'ExamReminderScheduler',
          'failed to schedule exam reminder',
          error: error,
          stackTrace: stackTrace,
          fields: {'examKey': exam.key},
        );
      }
    }

    await prefs.setString(_scheduledIdsKey, jsonEncode(newIds));
    AppLogger.I.info(
      'ExamReminderScheduler',
      'exam reminders rescheduled',
      fields: {'scheduled': newIds.length, 'upcoming': upcoming.length},
    );
  }

  /// Cancels all previously scheduled exam reminders.
  static Future<void> cancelAll({
    Future<SharedPreferences> Function()? prefsProvider,
  }) async {
    final prefs = await (prefsProvider ?? SharedPreferences.getInstance)();
    await _cancelPrevious(prefs);
  }

  static Future<void> _cancelPrevious(SharedPreferences prefs) async {
    final raw = prefs.getString(_scheduledIdsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          final ids = decoded.whereType<int>().toList();
          if (ids.isNotEmpty) await LocalNotifications.cancelIds(ids);
        }
      } catch (_) {}
      await prefs.remove(_scheduledIdsKey);
    }
  }
}
