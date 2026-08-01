import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:cqut_helper/manager/schedule_update_intents.dart';

class LocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'schedule_updates';
  static const String _channelName = '课表更新';
  static const String _channelDescription = '用于提示课表变化与更新信息';
  static const String _systemChannelId = 'system_alerts';
  static const String _systemChannelName = '系统告警';
  static const String _systemChannelDescription = '用于提示应用运行与日志异常';
  static const String _courseChannelId = 'course_reminders';
  static const String _courseChannelName = '课程提醒';
  static const String _courseChannelDescription = '用于在上课前提醒即将开始的课程';
  static const String _prefsKeyOpenScheduleUpdate =
      'schedule_open_update_from_notification';
  static const String _prefsKeyOpenCourseReminder =
      'schedule_open_course_reminder_from_notification';
  static const String payloadScheduleUpdate = 'schedule_update';

  static bool _initialized = false;
  static bool _timezoneInitialized = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    if (_initialized) return;
    if (!_timezoneInitialized) {
      tz_data.initializeTimeZones();
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
      _timezoneInitialized = true;
    }

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        await _handleTap(response.payload);
      },
    );

    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _courseChannelId,
          _courseChannelName,
          description: _courseChannelDescription,
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        const AndroidNotificationChannel(
          _systemChannelId,
          _systemChannelName,
          description: _systemChannelDescription,
          importance: Importance.high,
        ),
      );
    }

    _initialized = true;

    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details != null &&
        details.didNotificationLaunchApp &&
        details.notificationResponse?.payload != null) {
      await _handleTap(details.notificationResponse!.payload);
    }
  }

  static Future<bool> ensurePermission() async {
    if (!Platform.isAndroid) return false;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    final ok = await android.requestNotificationsPermission();
    return ok ?? false;
  }

  static Future<bool> canScheduleExactNotifications() async {
    if (!Platform.isAndroid) return false;
    await initialize();
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    return await android.canScheduleExactNotifications() ?? true;
  }

  static Future<bool> ensureCourseReminderPermissions() async {
    if (!await ensurePermission()) return false;
    if (await canScheduleExactNotifications()) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return false;
    final granted = await android.requestExactAlarmsPermission() ?? false;
    return granted && await canScheduleExactNotifications();
  }

  static Future<bool> consumeOpenScheduleUpdateFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_prefsKeyOpenScheduleUpdate) ?? false;
    if (v) {
      await prefs.remove(_prefsKeyOpenScheduleUpdate);
    }
    return v;
  }

  static Future<bool> consumeOpenCourseReminderFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_prefsKeyOpenCourseReminder) ?? false;
    if (value) await prefs.remove(_prefsKeyOpenCourseReminder);
    return value;
  }

  static Future<void> cancelAll() async {
    if (!Platform.isAndroid) return;
    await initialize();
    await _plugin.cancelAll();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKeyOpenScheduleUpdate);
    await prefs.remove(_prefsKeyOpenCourseReminder);
  }

  static Future<void> _handleTap(String? payload) async {
    if ((payload ?? '').startsWith('course_reminder|')) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKeyOpenCourseReminder, true);
      return;
    }
    if (payload != payloadScheduleUpdate) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyOpenScheduleUpdate, true);
    ScheduleUpdateIntents.requestOpenFromNotification();
  }

  static Future<void> showScheduleUpdate({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) async {
    if (!Platform.isAndroid) return;
    await initialize();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      ),
    );

    await _plugin.show(
      id ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> showSystemAlert({
    required String title,
    required String body,
    String? payload,
    int? id,
  }) async {
    if (!Platform.isAndroid) return;
    await initialize();

    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _systemChannelId,
        _systemChannelName,
        channelDescription: _systemChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      ),
    );

    await _plugin.show(
      id ?? DateTime.now().millisecondsSinceEpoch.remainder(1 << 31),
      title,
      body,
      details,
      payload: payload,
    );
  }

  static Future<void> scheduleCourseReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledAt,
    String? payload,
  }) async {
    if (!Platform.isAndroid || !scheduledAt.isAfter(DateTime.now())) return;
    await initialize();
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _courseChannelId,
        _courseChannelName,
        channelDescription: _courseChannelDescription,
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      tz.TZDateTime.from(scheduledAt, tz.local),
      details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
  }

  static Future<void> cancelIds(Iterable<int> ids) async {
    if (!Platform.isAndroid) return;
    await initialize();
    for (final id in ids) {
      await _plugin.cancel(id);
    }
  }
}
