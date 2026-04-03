import 'dart:io';

import 'package:flutter/services.dart';

class WidgetUpdater {
  static const MethodChannel _channel = MethodChannel('cqut/widget');

  static Future<void> updateTodayWidget({String? themeMode}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateTodayWidget', {
        if (themeMode != null) 'themeMode': themeMode,
      });
    } catch (_) {}
  }
}

