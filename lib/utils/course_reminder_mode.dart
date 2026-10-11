import 'dart:io';

import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CourseReminderPermissionStatus {
  final bool supported;
  final bool notificationGranted;
  final bool exactAlarmGranted;
  final bool dndGranted;
  final bool batteryOptimizationIgnored;
  final bool autoModeActive;
  final String? autoModeStatus;

  const CourseReminderPermissionStatus({
    this.supported = false,
    this.notificationGranted = false,
    this.exactAlarmGranted = false,
    this.dndGranted = false,
    this.batteryOptimizationIgnored = false,
    this.autoModeActive = false,
    this.autoModeStatus,
  });

  factory CourseReminderPermissionStatus.fromMap(Map<Object?, Object?> map) =>
      CourseReminderPermissionStatus(
        supported: map['supported'] == true,
        notificationGranted: map['notificationGranted'] == true,
        exactAlarmGranted: map['exactAlarmGranted'] == true,
        dndGranted: map['dndGranted'] == true,
        batteryOptimizationIgnored: map['batteryOptimizationIgnored'] == true,
        autoModeActive: map['autoModeActive'] == true,
        autoModeStatus: map['autoModeStatus'] as String?,
      );
}

@immutable
class CourseAutoModeInterval {
  final int startMillis;
  final int endMillis;
  const CourseAutoModeInterval({
    required this.startMillis,
    required this.endMillis,
  });
  Map<String, int> toMap() => {
    'startMillis': startMillis,
    'endMillis': endMillis,
  };
}

class CourseReminderMode {
  static const _channel = MethodChannel('cqut/course_reminders');
  @visibleForTesting
  static bool? debugIsAndroidOverride;
  static bool get _isAndroid => debugIsAndroidOverride ?? Platform.isAndroid;

  static Future<T?> _invoke<T>(String method, [Object? arguments]) async {
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } catch (error, stackTrace) {
      AppLogger.I.error(
        'CourseReminderMode',
        'native reminder operation failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'method': method},
      );
      rethrow;
    }
  }

  static Future<CourseReminderPermissionStatus> getStatus() async {
    if (!_isAndroid) return const CourseReminderPermissionStatus();
    final map = await _invoke<Map<Object?, Object?>>('getStatus');
    if (map == null) throw StateError('Missing reminder permission status');
    return CourseReminderPermissionStatus.fromMap(map);
  }

  static Future<bool> openSettings(String kind) async {
    if (!_isAndroid) return false;
    return await _invoke<bool>('openSettings', {'kind': kind}) ?? false;
  }

  static Future<void> replaceSchedule({
    required CourseAutoMode mode,
    required List<CourseAutoModeInterval> intervals,
  }) async {
    if (!_isAndroid) return;
    await _invoke<void>('replaceSchedule', {
      'mode': mode.name,
      'intervals': intervals.map((interval) => interval.toMap()).toList(),
    });
  }

  static Future<void> cancelAndRestore() async {
    if (!_isAndroid) return;
    await _invoke<void>('cancelAndRestore');
  }
}
