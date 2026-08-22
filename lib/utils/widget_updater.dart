import 'dart:io';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef WidgetMethodInvoker =
    Future<void> Function(String method, Map<String, Object?> arguments);

class WidgetUpdater {
  static const MethodChannel _channel = MethodChannel('cqut/widget');
  static const Duration _retryDelay = Duration(milliseconds: 120);

  @visibleForTesting
  static bool? debugIsAndroidOverride;

  @visibleForTesting
  static WidgetMethodInvoker? debugMethodInvoker;

  @visibleForTesting
  static Future<void> Function(Duration delay)? debugDelay;

  static Future<void> updateTodayWidget({
    String? themeMode,
    String? trigger,
  }) async {
    if (!(debugIsAndroidOverride ?? Platform.isAndroid)) return;
    final arguments = <String, Object?>{
      'themeMode': ?themeMode,
      'trigger': ?trigger,
    };
    final invoke = debugMethodInvoker ?? _invokePlatformMethod;

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        await invoke('updateTodayWidget', arguments);
        return;
      } catch (error, stackTrace) {
        final isFinalAttempt = attempt == 2;
        final log = isFinalAttempt ? AppLogger.I.error : AppLogger.I.warn;
        log(
          'WidgetUpdater',
          isFinalAttempt
              ? 'widget bridge failed after retry'
              : 'widget bridge failed; retrying',
          error: error,
          stackTrace: stackTrace,
          fields: {
            'attempt': attempt,
            'trigger': trigger ?? '',
            'hasThemeMode': themeMode != null && themeMode.isNotEmpty,
          },
        );
        if (isFinalAttempt) return;
        final delay = debugDelay;
        if (delay == null) {
          await Future<void>.delayed(_retryDelay);
        } else {
          await delay(_retryDelay);
        }
      }
    }
  }

  static Future<void> _invokePlatformMethod(
    String method,
    Map<String, Object?> arguments,
  ) async {
    await _channel.invokeMethod<void>(method, arguments);
  }

  @visibleForTesting
  static void resetDebugOverrides() {
    debugIsAndroidOverride = null;
    debugMethodInvoker = null;
    debugDelay = null;
  }
}

/// Suppresses the launch-time `resumed` callback while repairing widgets when
/// an existing app session actually returns from the background.
class WidgetResumeRefreshGate {
  bool _leftForeground = false;

  bool shouldRefresh(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        final shouldRefresh = _leftForeground;
        _leftForeground = false;
        return shouldRefresh;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _leftForeground = true;
        return false;
      case AppLifecycleState.inactive:
        return false;
    }
  }
}
