import 'dart:io';

import 'package:flutter/services.dart';

class AndroidBackgroundRestrictions {
  static const MethodChannel _channel = MethodChannel('cqut/power');

  static Future<String?> manufacturer() async {
    if (!Platform.isAndroid) return null;
    try {
      final v = await _channel.invokeMethod<String>('manufacturer');
      if (v == null || v.trim().isEmpty) return null;
      return v;
    } catch (_) {
      return null;
    }
  }

  static Future<bool?> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
    } catch (_) {
      return null;
    }
  }

  static Future<bool?> isBackgroundRestricted() async {
    if (!Platform.isAndroid) return null;
    try {
      return await _channel.invokeMethod<bool>('isBackgroundRestricted');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'requestIgnoreBatteryOptimizations',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openBatteryOptimizationSettings',
          ) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAutoStartSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAutoStartSettings') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openAppDetailsSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('openAppDetailsSettings') ?? false;
    } catch (_) {
      return false;
    }
  }
}

