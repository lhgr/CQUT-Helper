import 'dart:async';

import 'package:cqut_helper/manager/background_image_temp_manager.dart';
import 'package:cqut_helper/manager/academic_calendar_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_navigation.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

Future<void> bootstrapAndRunApp(Widget Function() rootBuilder) async {
  AppLogger.I.installGlobalErrorHandlers();
  await AppLogger.I.init(
    minLevel: kDebugMode ? LogLevel.debug : LogLevel.info,
    enableConsole: true,
    enableFile: true,
    source: 'foreground',
  );
  WidgetsBinding.instance.addObserver(_DiagnosticLifecycleObserver());
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  final staleBackgroundCleanup = BackgroundImageTempManager.cleanup();
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
  await staleBackgroundCleanup;

  runApp(rootBuilder());
  unawaited(ScheduleUpdateWorker.syncFromPreferences());
  // Calendar service is deliberately slow and independent of notice
  // enhancement. Start it after the first frame without blocking startup.
  unawaited(AcademicCalendarManager.instance.initializeFromPreferences());
}

class _DiagnosticLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AppLogger.I.pruneLogs());
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(AppLogger.I.flush());
    }
  }
}

Future<void> _preloadScheduleBackground() async {
  final scheduleSettings = ScheduleSettingsManager();
  await scheduleSettings.load();
  final backgroundPath = scheduleSettings.layoutSettings.backgroundImagePath
      ?.trim();
  if (backgroundPath == null || backgroundPath.isEmpty) return;
  await ScheduleBackground.preloadFile(backgroundPath);
}
