import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WidgetNavigationRequest {
  final int token;
  final int dayOffset;
  final String? eventName;
  final String? eventId;

  const WidgetNavigationRequest({
    required this.token,
    required this.dayOffset,
    this.eventName,
    this.eventId,
  });

  bool get hasCourse =>
      (eventId?.trim().isNotEmpty ?? false) ||
      (eventName?.trim().isNotEmpty ?? false);
}

class WidgetNavigation {
  static const MethodChannel _channel = MethodChannel('cqut/navigation');
  static final ValueNotifier<WidgetNavigationRequest?> request =
      ValueNotifier<WidgetNavigationRequest?>(null);
  static int _nextToken = 0;

  static Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'widgetNavigation') {
        _publish(call.arguments);
      }
    });
    try {
      final initial = await _channel.invokeMapMethod<String, dynamic>(
        'getInitialWidgetNavigation',
      );
      if (initial != null) _publish(initial);
    } catch (_) {}
  }

  static void _publish(Object? raw) {
    if (raw is! Map) return;
    final map = raw.cast<Object?, Object?>();
    request.value = WidgetNavigationRequest(
      token: ++_nextToken,
      dayOffset: (map['dayOffset'] as num?)?.toInt() ?? 0,
      eventName: map['eventName']?.toString(),
      eventId: map['eventId']?.toString(),
    );
  }
}
