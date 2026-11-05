import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cqut_helper/utils/schedule_date.dart';

class WidgetNavigationRequest {
  final int token;
  final int dayOffset;
  final String? eventName;
  final String? eventId;
  final DateTime? date;
  final String action;

  const WidgetNavigationRequest({
    required this.token,
    required this.dayOffset,
    this.eventName,
    this.eventId,
    this.date,
    this.action = 'open',
  });

  DateTime targetDate({DateTime? now}) {
    if (date != null) return date!;
    final today = now ?? DateTime.now();
    return DateTime(today.year, today.month, today.day + dayOffset);
  }

  bool get hasCourse =>
      (eventId?.trim().isNotEmpty ?? false) ||
      (eventName?.trim().isNotEmpty ?? false);
}

class WidgetNavigation {
  static const MethodChannel _channel = MethodChannel('cqut/navigation');
  static final ValueNotifier<WidgetNavigationRequest?> request =
      ValueNotifier<WidgetNavigationRequest?>(null);
  static int _nextToken = 0;
  static int _consumedSyncToken = 0;

  @visibleForTesting
  static bool? debugIsSupportedOverride;

  static bool consumeSyncAction(WidgetNavigationRequest navigation) {
    if (navigation.action != 'sync' || navigation.token <= _consumedSyncToken) {
      return false;
    }
    _consumedSyncToken = navigation.token;
    return true;
  }

  static Future<void> initialize() async {
    if (!(debugIsSupportedOverride ?? (Platform.isAndroid || Platform.isIOS))) {
      return;
    }
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
      date: _parseDate(map['date']),
      action: map['action'] == 'sync' ? 'sync' : 'open',
    );
  }

  static DateTime? _parseDate(Object? value) {
    final raw = value?.toString() ?? '';
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
    return ScheduleDate.tryParseWeekDate(raw);
  }
}
