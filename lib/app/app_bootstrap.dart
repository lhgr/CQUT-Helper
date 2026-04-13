import 'dart:async';

import 'package:cqut_helper/manager/preview_cache_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
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
  await LocalNotifications.initialize();
  await ScheduleUpdateWorker.initialize();

  runApp(rootBuilder());
  unawaited(ScheduleUpdateWorker.syncFromPreferences());
  unawaited(PreviewCacheManager.cleanupIfNeeded());
}
