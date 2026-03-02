import 'dart:convert';
import 'dart:io';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut/utils/course_reminder_planner.dart';
import 'package:cqut/utils/local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CourseReminderManager {
  static const String _prefsKeyEnabled = 'course_reminder_enabled';
  static const String _prefsKeyAdvanceMinutes =
      'course_reminder_advance_minutes';
  static const String _prefsKeyAutoSound = 'course_reminder_auto_sound';
  static const String _prefsKeySoundMode = 'course_reminder_sound_mode';
  static const String _prefsKeyDaysAhead = 'course_reminder_days_ahead';
  static const String _prefsKeyScheduledIds = 'course_reminder_scheduled_ids';

  static const int _refreshAlarmId = 901000001;

  static CourseReminderSettings defaultSettings() {
    return const CourseReminderSettings(
      enabled: false,
      advanceMinutes: 10,
      autoSwitchSoundMode: false,
      soundMode: CourseReminderSoundMode.vibrate,
      daysAhead: 2,
    );
  }

  static Future<CourseReminderSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool(_prefsKeyEnabled) ?? false;
    final advance = (prefs.getInt(_prefsKeyAdvanceMinutes) ?? 10).clamp(1, 120);
    final autoSound = prefs.getBool(_prefsKeyAutoSound) ?? false;
    final soundRaw = prefs.getString(_prefsKeySoundMode) ?? 'vibrate';
    final sound = soundRaw == 'silent'
        ? CourseReminderSoundMode.silent
        : CourseReminderSoundMode.vibrate;
    final daysAhead = (prefs.getInt(_prefsKeyDaysAhead) ?? 2).clamp(0, 14);

    return CourseReminderSettings(
      enabled: enabled,
      advanceMinutes: advance,
      autoSwitchSoundMode: autoSound,
      soundMode: sound,
      daysAhead: daysAhead,
    );
  }

  static Future<void> saveSettings(CourseReminderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, settings.enabled);
    await prefs.setInt(_prefsKeyAdvanceMinutes, settings.advanceMinutes);
    await prefs.setBool(_prefsKeyAutoSound, settings.autoSwitchSoundMode);
    await prefs.setString(
      _prefsKeySoundMode,
      settings.soundMode == CourseReminderSoundMode.silent
          ? 'silent'
          : 'vibrate',
    );
    await prefs.setInt(_prefsKeyDaysAhead, settings.daysAhead);
  }

  static Future<void> sync() async {
    if (!Platform.isAndroid) return;

    final settings = await loadSettings();
    if (!settings.enabled) {
      await _cancelAllScheduled();
      await AndroidAlarmManager.cancel(_refreshAlarmId);
      return;
    }

    await LocalNotifications.initialize();

    final controller = ScheduleController();
    final cached = await controller.loadFromCache();
    if (cached == null) return;
    controller.processLoadedData(cached);
    await controller.loadTimeInfoFromCacheIfAny();
    await controller.refreshTimeInfoIfEnabled();

    final candidateWeeks = await _loadCandidateWeeks(
      controller: controller,
      current: cached,
      daysAhead: settings.daysAhead,
    );

    final planned = CourseReminderPlanner.plan(
      now: DateTime.now(),
      settings: settings,
      candidateWeeks: candidateWeeks,
      timeInfoList: controller.timeInfoList,
    );

    await _replaceScheduledAlarms(planned);

    await AndroidAlarmManager.periodic(
      const Duration(hours: 8),
      _refreshAlarmId,
      courseReminderRefreshAlarm,
      exact: false,
      allowWhileIdle: false,
      wakeup: false,
      rescheduleOnReboot: true,
    );
  }

  static Future<bool> dndPermissionGranted() async {
    return false;
  }

  static Future<void> openDndSettings() async {
    return;
  }

  static Future<void> testNow({
    required bool autoSwitchSoundMode,
    required CourseReminderSoundMode soundMode,
  }) async {
    if (!Platform.isAndroid) return;
    await LocalNotifications.initialize();
    await LocalNotifications.showCourseReminder(
      title: '上课提醒测试',
      body: '这是一条手动触发的测试提醒',
      payload: LocalNotifications.payloadCourseReminderTest,
    );
  }

  static Future<List<ScheduleData>> _loadCandidateWeeks({
    required ScheduleController controller,
    required ScheduleData current,
    required int daysAhead,
  }) async {
    final list = <ScheduleData>[current];
    final wList = current.weekList;
    final currentWeekStr = current.weekNum;
    final yearTerm = current.yearTerm;

    if (daysAhead <= 7 ||
        wList == null ||
        currentWeekStr == null ||
        yearTerm == null) {
      return list;
    }

    final idx = wList.indexOf(currentWeekStr);
    if (idx == -1) return list;

    final needWeeks = (daysAhead / 7).ceil();
    for (int offset = 1; offset <= needWeeks; offset++) {
      final i = idx + offset;
      if (i < 0 || i >= wList.length) break;
      final w = wList[i];
      await controller.ensureWeekLoaded(w, yearTerm);
      final wInt = int.tryParse(w) ?? 0;
      final data = controller.weekCache[wInt];
      if (data != null) list.add(data);
    }
    return list;
  }

  static int _stableIdFor(String input) {
    final bytes = utf8.encode(input);
    final digest = sha1.convert(bytes).bytes;
    final v =
        (digest[0] << 24) | (digest[1] << 16) | (digest[2] << 8) | digest[3];
    return v & 0x7fffffff;
  }

  static Future<void> _cancelAllScheduled() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_prefsKeyScheduledIds) ?? const <String>[];
    for (final raw in list) {
      final id = int.tryParse(raw);
      if (id == null) continue;
      await AndroidAlarmManager.cancel(id);
    }
    await prefs.remove(_prefsKeyScheduledIds);
  }

  static Future<void> _replaceScheduledAlarms(
    List<PlannedCourseReminder> planned,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final prev = prefs.getStringList(_prefsKeyScheduledIds) ?? const <String>[];
    for (final raw in prev) {
      final id = int.tryParse(raw);
      if (id == null) continue;
      await AndroidAlarmManager.cancel(id);
    }

    final nextIds = <String>[];
    for (final r in planned) {
      final uniqueKey = '${r.key}|${r.classStartAt.toIso8601String()}';
      final alarmId = _stableIdFor(uniqueKey);

      final title = '即将上课：${r.courseName.isEmpty ? '课程' : r.courseName}';
      final time = _formatHm(r.classStartAt);
      final where = r.location.isEmpty ? '' : ' @${r.location}';
      final sessions = r.startSession == r.endSession
          ? '第${r.startSession}节'
          : '第${r.startSession}-${r.endSession}节';
      final teacher = r.teacher.isEmpty ? '' : ' · ${r.teacher}';
      final body = '$time $sessions$where$teacher';

      try {
        final ok = await AndroidAlarmManager.oneShotAt(
          r.fireAt,
          alarmId,
          courseReminderAlarm,
          exact: true,
          allowWhileIdle: true,
          wakeup: true,
          rescheduleOnReboot: true,
          params: <String, dynamic>{'title': title, 'body': body},
        );
        if (ok) nextIds.add(alarmId.toString());
      } catch (_) {
        try {
          final ok = await AndroidAlarmManager.oneShotAt(
            r.fireAt,
            alarmId,
            courseReminderAlarm,
            exact: false,
            allowWhileIdle: false,
            wakeup: false,
            rescheduleOnReboot: true,
            params: <String, dynamic>{'title': title, 'body': body},
          );
          if (ok) nextIds.add(alarmId.toString());
        } catch (_) {}
      }
    }

    await prefs.setStringList(_prefsKeyScheduledIds, nextIds);
  }

  static String _formatHm(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}

@pragma('vm:entry-point')
void courseReminderAlarm(int id, Map<String, dynamic> params) async {
  try {
    await LocalNotifications.initialize();

    final title = (params['title'] ?? '上课提醒').toString();
    final body = (params['body'] ?? '').toString();
    await LocalNotifications.showCourseReminder(
      id: id,
      title: title,
      body: body,
      payload: LocalNotifications.payloadCourseReminder,
    );
  } catch (_) {}
}

@pragma('vm:entry-point')
void courseReminderRefreshAlarm(int id) async {
  try {
    await CourseReminderManager.sync();
  } catch (_) {}
}
