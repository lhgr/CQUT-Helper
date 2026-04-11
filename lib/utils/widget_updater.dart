import 'dart:io';

import 'package:flutter/services.dart';

class WidgetUpdater {
  static const MethodChannel _channel = MethodChannel('cqut/widget');

  static Future<void> updateTodayWidget() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateTodayWidget');
    } catch (_) {}
  }
}

