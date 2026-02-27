import 'package:cqut/manager/theme_manager.dart';
import 'package:cqut/manager/schedule_update_worker.dart';
import 'package:cqut/routes/Routes.dart';
import 'package:cqut/utils/app_logger.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cqut/utils/local_notifications.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await AppLogger.I.init(
    minLevel: kDebugMode ? LogLevel.debug : LogLevel.info,
    enableConsole: true,
    enableFile: true,
  );
  AppLogger.I.installGlobalErrorHandlers();
  AppLogger.I.info(
    'App',
    'startup',
    fields: {'log_file': AppLogger.I.logFilePath},
  );

  // 初始化 Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 设置沉浸式状态栏
  await ThemeManager().init();
  await LocalNotifications.initialize();
  await ScheduleUpdateWorker.initialize();
  await ScheduleUpdateWorker.syncFromPreferences();
  runApp(getRootWidget());
}
