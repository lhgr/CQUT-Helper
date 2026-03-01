import 'dart:async';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:cqut/manager/course_reminder_manager.dart';
import 'package:cqut/manager/schedule_update_worker.dart';
import 'package:cqut/manager/theme_manager.dart';
import 'package:cqut/utils/app_logger.dart';
import 'package:cqut/utils/local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../firebase_options.dart';

Future<void> bootstrapAndRunApp(Widget Function() rootBuilder) async {
  final logDate = DateTime.now().toIso8601String().split('T').first;
  await AppLogger.I.init(
    minLevel: kDebugMode ? LogLevel.debug : LogLevel.info,
    enableConsole: true,
    enableFile: true,
    fileName: 'cqut_$logDate.log',
  );
  AppLogger.I.installGlobalErrorHandlers();
  AppLogger.I.info(
    'App',
    'startup',
    fields: {'log_file': AppLogger.I.logFilePath},
  );

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await ThemeManager().init();
  await AndroidAlarmManager.initialize();
  await LocalNotifications.initialize();
  await ScheduleUpdateWorker.initialize();

  runApp(rootBuilder());
  unawaited(CourseReminderManager.sync());
  unawaited(ScheduleUpdateWorker.syncFromPreferences());
}
