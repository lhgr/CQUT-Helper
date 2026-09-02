import 'dart:async';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_navigation.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

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

  await ThemeManager().init();
  final scheduleBackgroundReady = _preloadScheduleBackground();
  await LocalNotifications.initialize();
  await ScheduleUpdateWorker.initialize();
  await WidgetNavigation.initialize();
  await scheduleBackgroundReady;

  runApp(rootBuilder());
  unawaited(ScheduleUpdateWorker.syncFromPreferences());
}

Future<void> _preloadScheduleBackground() async {
  final scheduleSettings = ScheduleSettingsManager();
  await scheduleSettings.load();
  final backgroundPath = scheduleSettings.layoutSettings.backgroundImagePath
      ?.trim();
  if (backgroundPath == null || backgroundPath.isEmpty) return;
  await ScheduleBackground.preloadFile(backgroundPath);
}
