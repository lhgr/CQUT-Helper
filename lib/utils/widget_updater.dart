import 'dart:io';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/widget_snapshot.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

typedef WidgetMethodInvoker = Future<void> Function(
  String method,
  Map<String, Object?> arguments,
);

enum WidgetUpdateResult { accepted, failed, notSupported }

class WidgetUpdater {
  static const MethodChannel _channel = MethodChannel('cqut/widget');
  static const Duration _retryDelay = Duration(milliseconds: 120);

  @visibleForTesting
  static bool? debugIsAndroidOverride;

  @visibleForTesting
  static bool? debugIsIOSOverride;

  static Future<void> _iosUpdates = Future<void>.value();

  @visibleForTesting
  static WidgetMethodInvoker? debugMethodInvoker;

  @visibleForTesting
  static Future<void> Function(Duration delay)? debugDelay;

  static Future<WidgetUpdateResult> updateTodayWidget({
    String? themeMode,
    String? trigger,
  }) {
    final isIOS = debugIsIOSOverride ?? Platform.isIOS;
    Future<WidgetUpdateResult> update() => AppLogger.I.runWithTraceIdAsync(
      AppLogger.I.currentTraceId ?? AppLogger.I.newTraceId(),
      () => _updateTodayWidget(themeMode: themeMode, trigger: trigger),
    );
    if (!isIOS) return update();
    // Build after earlier deliveries complete so retries cannot overwrite a
    // newer account, logout, customization, or theme snapshot.
    final result = _iosUpdates.then((_) => update());
    _iosUpdates = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static Future<WidgetUpdateResult> _updateTodayWidget({
    String? themeMode,
    String? trigger,
  }) async {
    final isIOS = debugIsIOSOverride ?? Platform.isIOS;
    if (!(debugIsAndroidOverride ?? Platform.isAndroid) && !isIOS) {
      return WidgetUpdateResult.notSupported;
    }
    final arguments = <String, Object?>{
      'themeMode': ?themeMode,
      'trigger': ?trigger,
      'operationId': ?AppLogger.I.currentTraceId,
    };
    final invoke = debugMethodInvoker ?? _invokePlatformMethod;
    AppLogger.I.info(
      'WidgetUpdater',
      'widget update started',
      fields: {'stage': 'widget_bridge', 'trigger': trigger},
    );

    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        if (isIOS) {
          arguments['snapshotJson'] = await WidgetSnapshot.encode(
            themeMode: themeMode,
          );
        }
        await invoke('updateTodayWidget', arguments);
        AppLogger.I.info(
          'WidgetUpdater',
          'widget update completed',
          fields: {
            'stage': 'widget_bridge',
            'outcome': 'succeeded',
            'trigger': trigger,
          },
        );
        return WidgetUpdateResult.accepted;
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
            'stage': 'widget_bridge',
            'outcome': isFinalAttempt ? 'failed' : 'retrying',
          },
        );
        if (isFinalAttempt) return WidgetUpdateResult.failed;
        final delay = debugDelay;
        if (delay == null) {
          await Future<void>.delayed(_retryDelay);
        } else {
          await delay(_retryDelay);
        }
      }
    }
    return WidgetUpdateResult.failed;
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
    debugIsIOSOverride = null;
    debugMethodInvoker = null;
    debugDelay = null;
  }
}
