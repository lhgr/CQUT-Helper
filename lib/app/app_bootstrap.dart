import 'dart:async';

import 'package:cqut_helper/manager/background_image_temp_manager.dart';
import 'package:cqut_helper/manager/academic_calendar_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/manager/onboarding_manager.dart';
import 'package:cqut_helper/pages/ClassSchedule/widgets/schedule_background.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_navigation.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

Future<void> bootstrapAndRunApp(Widget Function() rootBuilder) async {
  final startupTimer = Stopwatch()..start();
  AppLogger.I.installGlobalErrorHandlers();
  await AppLogger.I.init(
    minLevel: kDebugMode ? LogLevel.debug : LogLevel.info,
    enableConsole: true,
    enableFile: true,
    source: 'foreground',
  );
  AppLogger.I.info(
    'App',
    'startup stage completed',
    fields: {
      'stage': 'logger',
      'duration_ms': startupTimer.elapsedMilliseconds,
    },
  );
  WidgetsBinding.instance.addObserver(_DiagnosticLifecycleObserver());
  await _runStartupStage(
    'orientation',
    () => SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
  );
  AppLogger.I.info(
    'App',
    'startup',
    fields: {'log_file': AppLogger.I.logFilePath},
  );

  await _runStartupStage('theme', ThemeManager().init);
  await _runStartupStage('onboarding', OnboardingManager.instance.initialize);
  final scheduleBackgroundReady = _runStartupStage(
    'schedule_background',
    _preloadScheduleBackground,
  );
  await _runStartupStage('notifications', LocalNotifications.initialize);
  await _runStartupStage('schedule_worker', ScheduleUpdateWorker.initialize);
  await _runStartupStage('widget_navigation', WidgetNavigation.initialize);
  await scheduleBackgroundReady;

  WidgetsBinding.instance.addPostFrameCallback((_) {
    AppLogger.I.info(
      'App',
      'first frame completed',
      fields: {
        'stage': 'first_frame',
        'duration_ms': startupTimer.elapsedMilliseconds,
      },
    );
    unawaited(_runAfterFirstFrame());
  });
  runApp(rootBuilder());
}

Future<void> _runAfterFirstFrame() async {
  await Future.wait([
    _runBackgroundStartupStage('background_temp_cleanup', () async {
      await BackgroundImageTempManager.cleanup(throwOnFailure: true);
    }),
    _runBackgroundStartupStage('widget_theme', () async {
      final result = await ThemeManager().syncWidgetTheme();
      if (result == WidgetUpdateResult.failed) {
        throw StateError('Initial widget theme publication failed');
      }
    }),
    _runBackgroundStartupStage(
      'schedule_preferences',
      ScheduleUpdateWorker.syncFromPreferences,
    ),
    if (!LocalNotifications.isIOS)
      _runBackgroundStartupStage(
        'academic_calendar',
        AcademicCalendarManager.instance.initializeFromPreferences,
      ),
  ]);
}

Future<void> _runBackgroundStartupStage(
  String stage,
  Future<void> Function() action,
) async {
  try {
    await _runStartupStage(stage, action);
  } catch (_) {
    // Each optional stage reports its own error and cannot block the others.
  }
}

Future<void> _runStartupStage(
  String stage,
  Future<void> Function() action,
) async {
  final timer = Stopwatch()..start();
  try {
    await action();
    AppLogger.I.info(
      'App',
      'startup stage completed',
      fields: {'stage': stage, 'duration_ms': timer.elapsedMilliseconds},
    );
  } catch (error, stackTrace) {
    AppLogger.I.error(
      'App',
      'startup stage failed',
      error: error,
      stackTrace: stackTrace,
      fields: {'stage': stage, 'duration_ms': timer.elapsedMilliseconds},
    );
    rethrow;
  }
}

class _DiagnosticLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(AppLogger.I.pruneLogs());
      if (LocalNotifications.isIOS) {
        unawaited(WidgetUpdater.updateTodayWidget(trigger: 'app_resumed'));
      }
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
