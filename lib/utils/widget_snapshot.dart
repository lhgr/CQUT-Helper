import 'dart:convert';

import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One account-scoped payload shared atomically with the iOS extension.
class WidgetSnapshot {
  const WidgetSnapshot._();

  static Future<String> encode({String? themeMode}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = (prefs.getString('account') ?? '').trim();
    final term = userId.isEmpty ? '' : _pin(prefs, 'term', userId);
    final week = userId.isEmpty
        ? null
        : int.tryParse(_pin(prefs, 'week', userId));
    final projection = userId.isEmpty
        ? null
        : _decodeMap(
            prefs.getString('schedule_widget_calendar_projection_v1_$userId'),
          );
    final validProjection =
        projection?['year_term'] == term && projection?['schema_version'] == 1
        ? projection
        : null;
    final refresh = userId.isEmpty
        ? null
        : await ScheduleRefreshState.load(userId);
    final state = switch (refresh?.widgetState) {
      ScheduleWidgetRefreshState.loading => 'loading',
      ScheduleWidgetRefreshState.failed =>
        refresh?.failure == ScheduleWidgetRefreshFailure.credentialInvalid
            ? 'credential_invalid'
            : 'failed',
      _ =>
        validProjection == null || refresh?.lastSuccessfulRefreshAt == null
            ? 'needs_sync'
            : 'normal',
    };
    final rawClocks = _decodeMap(
      prefs.getString('schedule_time_info_cache_v1'),
    )?['items'];
    final rawColors = userId.isEmpty
        ? null
        : _decodeMap(
            prefs.getString('schedule_course_color_map_v1_$userId|$term'),
          );
    final mode = themeMode ?? prefs.getString('theme_mode');
    return jsonEncode({
      'schemaVersion': 1,
      'generatedAt': DateTime.now().millisecondsSinceEpoch,
      'activeUserId': userId,
      'yearTerm': term,
      'pinnedWeek': ?week,
      'calendarProjection': validProjection,
      'sessionClocks': [
        if (rawClocks is List)
          for (final item in rawClocks.whereType<Map>())
            if (item['sessionNum'] is num &&
                item['startTime'] is String &&
                item['endTime'] is String)
              {
                'sessionNum': (item['sessionNum'] as num).toInt(),
                'startTime': item['startTime'],
                'endTime': item['endTime'],
              },
      ],
      'courseColorMap': {
        for (final entry
            in rawColors?.entries ?? const <MapEntry<String, dynamic>>[])
          if (entry.value is num) entry.key: (entry.value as num).toInt(),
      },
      'themeMode': switch (mode) {
        'light' || 'ThemeMode.light' => 'light',
        'dark' || 'ThemeMode.dark' => 'dark',
        _ => 'system',
      },
      'refresh': {
        'state': state,
        'lastSuccessfulAt':
            refresh?.lastSuccessfulRefreshAt?.millisecondsSinceEpoch,
        'failure': refresh?.failure?.name,
      },
    });
  }

  static String _pin(SharedPreferences prefs, String name, String userId) {
    final pinned = (prefs.getString('schedule_widget_${name}_$userId') ?? '')
        .trim();
    return pinned.isNotEmpty
        ? pinned
        : (prefs.getString('schedule_last_${name}_$userId') ?? '').trim();
  }

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
