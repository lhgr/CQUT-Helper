import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/ClassSchedule/schedule_update_intents.dart';

class LocalNotifications {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'schedule_updates';
  static const String _channelName = '课表更新';
  static const String _channelDescription = '用于提示课表变化与更新信息';
  static const String _prefsKeyOpenScheduleUpdate =
      'schedule_open_update_from_notification';
  static const String payloadScheduleUpdate = 'schedule_update';

  static bool _initialized = false;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    if (_initialized) return;

    const initSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/launcher_icon'),
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        await _handleTap(response.payload);
      },
    );

    final android =
        _plugin
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
    final android =
        _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >();
    if (android == null) return false;
    final ok = await android.requestNotificationsPermission();
    return ok ?? false;
  }

  static Future<bool> consumeOpenScheduleUpdateFlag() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getBool(_prefsKeyOpenScheduleUpdate) ?? false;
    if (v) {
      await prefs.remove(_prefsKeyOpenScheduleUpdate);
    }
    return v;
  }

  static Future<void> _handleTap(String? payload) async {
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
}
