import 'dart:convert';

import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/manager/schedule_update_worker.dart';
import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppBackupPreview {
  final int version;
  final DateTime createdAt;
  final String sourceAccount;
  final int preferenceCount;
  final int coursePreferenceCount;

  const AppBackupPreview({
    required this.version,
    required this.createdAt,
    required this.sourceAccount,
    required this.preferenceCount,
    required this.coursePreferenceCount,
  });
}

class AppBackupRestoreResult {
  final int preferenceCount;
  final int coursePreferenceCount;

  const AppBackupRestoreResult({
    required this.preferenceCount,
    required this.coursePreferenceCount,
  });
}

class AppBackupService {
  static const int currentVersion = 1;

  static const Set<String> _allowedSettings = {
    'schedule_show_weekend',
    'schedule_time_info_enabled',
    'schedule_course_reminders_enabled',
    'schedule_default_reminder_minutes',
    'schedule_display_density',
    'schedule_default_home_tab',
    'schedule_grid_cell_width',
    'schedule_grid_cell_height',
    'schedule_show_grid_lines',
    'schedule_background_opacity',
    'schedule_background_blur',
    'schedule_card_hide_location',
    'schedule_card_hide_teacher',
    'schedule_card_remove_campus_prefix',
    'schedule_card_horizontal_center',
    'schedule_card_vertical_center',
    'schedule_card_radius',
    'schedule_card_text_scale',
    'schedule_card_opacity',
    'theme_mode',
    'is_system_color',
    'custom_color',
    'theme_color_source',
    'schedule_background_theme_color',
    'wing_color_unlocked',
    'predictive_back_gesture_disabled',
  };

  static Future<String> createBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final account = (prefs.getString('account') ?? '').trim();
    if (account.isEmpty) throw StateError('请先登录后再备份');
    final settings = <String, Object?>{};
    final colorPrefix = 'schedule_course_color_map_v1_$account|';
    final messageKey = 'schedule_message_history_v1_$account';
    for (final key in prefs.getKeys()) {
      if (_allowedSettings.contains(key) ||
          key.startsWith(colorPrefix) ||
          key == messageKey) {
        settings[key] = prefs.get(key);
      }
    }
    final courses = await ScheduleCustomizationManager.instance
        .exportCoursePreferences(account);
    return const JsonEncoder.withIndent('  ').convert({
      'format': 'cqut-helper-backup',
      'version': currentVersion,
      'createdAt': DateTime.now().toIso8601String(),
      'sourceAccount': account,
      'settings': settings,
      'coursePreferences': courses,
    });
  }

  static AppBackupPreview preview(String content) {
    final root = _decode(content);
    final settings = root['settings'];
    final courses = root['coursePreferences'];
    return AppBackupPreview(
      version: (root['version'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse((root['createdAt'] ?? '').toString())?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      sourceAccount: (root['sourceAccount'] ?? '').toString(),
      preferenceCount: settings is Map ? settings.length : 0,
      coursePreferenceCount: courses is List ? courses.length : 0,
    );
  }

  static Future<AppBackupRestoreResult> restore(String content) async {
    final root = _decode(content);
    final prefs = await SharedPreferences.getInstance();
    final account = (prefs.getString('account') ?? '').trim();
    if (account.isEmpty) throw StateError('请先登录后再恢复');
    final settings = (root['settings'] as Map?)?.cast<String, dynamic>() ?? {};
    var restoredSettings = 0;
    final sourceAccount = (root['sourceAccount'] ?? '').toString().trim();
    for (final entry in settings.entries) {
      var key = entry.key;
      if (sourceAccount.isNotEmpty &&
          key.startsWith('schedule_course_color_map_v1_$sourceAccount|')) {
        key = key.replaceFirst(
          'schedule_course_color_map_v1_$sourceAccount|',
          'schedule_course_color_map_v1_$account|',
        );
      } else if (sourceAccount.isNotEmpty &&
          key == 'schedule_message_history_v1_$sourceAccount') {
        key = 'schedule_message_history_v1_$account';
      } else if (!_allowedSettings.contains(key)) {
        continue;
      }
      if (await _setPreference(prefs, key, entry.value)) restoredSettings++;
    }
    final rawCourses = root['coursePreferences'];
    final courses = rawCourses is List
        ? rawCourses
              .whereType<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    final restoredCourses = await ScheduleCustomizationManager.instance
        .importCoursePreferences(userId: account, rows: courses);
    CourseColorAssignmentManager.instance.resetInMemoryCache();
    ScheduleSettingsManager.settingsEpoch.value++;
    ScheduleSettingsManager.experienceEpoch.value++;
    await ThemeManager().init();
    await CourseReminderScheduler.rescheduleForUser(account);
    await ScheduleUpdateWorker.syncFromPreferences();
    return AppBackupRestoreResult(
      preferenceCount: restoredSettings,
      coursePreferenceCount: restoredCourses,
    );
  }

  static Map<String, dynamic> _decode(String content) {
    final decoded = jsonDecode(content);
    if (decoded is! Map) throw const FormatException('备份文件格式错误');
    final root = decoded.cast<String, dynamic>();
    if (root['format'] != 'cqut-helper-backup') {
      throw const FormatException('这不是 CQUT Helper 备份文件');
    }
    final version = (root['version'] as num?)?.toInt() ?? 0;
    if (version <= 0 || version > currentVersion) {
      throw const FormatException('备份版本不受支持，请升级应用后重试');
    }
    return root;
  }

  static Future<bool> _setPreference(
    SharedPreferences prefs,
    String key,
    Object? value,
  ) async {
    if (value is bool) return prefs.setBool(key, value);
    if (value is int) return prefs.setInt(key, value);
    if (value is double) return prefs.setDouble(key, value);
    if (value is String) return prefs.setString(key, value);
    if (value is List && value.every((item) => item is String)) {
      return prefs.setStringList(key, value.cast<String>());
    }
    return false;
  }
}
