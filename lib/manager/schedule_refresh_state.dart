import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

enum ScheduleWidgetRefreshState { idle, loading, failed }

enum ScheduleWidgetRefreshFailure { credentialInvalid, generic }

class ScheduleRefreshSnapshot {
  final DateTime? lastSuccessfulRefreshAt;
  final ScheduleWidgetRefreshState widgetState;
  final ScheduleWidgetRefreshFailure? failure;

  const ScheduleRefreshSnapshot({
    required this.lastSuccessfulRefreshAt,
    required this.widgetState,
    required this.failure,
  });
}

class ScheduleRefreshState {
  static const String _lastSuccessfulRefreshAtPrefix =
      'schedule_last_successful_refresh_at_';
  static const String _widgetRefreshStatePrefix =
      'schedule_widget_refresh_state_';
  static const String _widgetRefreshFailurePrefix =
      'schedule_widget_refresh_failure_';
  static const String _widgetRefreshTokenPrefix =
      'schedule_widget_refresh_token_';

  static String _lastSuccessfulRefreshAtKey(String userId) =>
      '$_lastSuccessfulRefreshAtPrefix${userId.trim()}';

  static String _widgetRefreshStateKey(String userId) =>
      '$_widgetRefreshStatePrefix${userId.trim()}';

  static String _widgetRefreshFailureKey(String userId) =>
      '$_widgetRefreshFailurePrefix${userId.trim()}';

  static String _widgetRefreshTokenKey(String userId) =>
      '$_widgetRefreshTokenPrefix${userId.trim()}';

  static Future<ScheduleRefreshSnapshot> load(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedUserId = userId.trim();
    var rawTime = prefs.getString(
      _lastSuccessfulRefreshAtKey(normalizedUserId),
    );
    if (DateTime.tryParse(rawTime ?? '') == null) {
      final migratedAt = _migrateLegacyRefreshAt(
        prefs: prefs,
        userId: normalizedUserId,
      );
      if (migratedAt != null) {
        rawTime = migratedAt.toIso8601String();
        await prefs.setString(
          _lastSuccessfulRefreshAtKey(normalizedUserId),
          rawTime,
        );
      }
    }
    final rawState =
        prefs.getString(_widgetRefreshStateKey(normalizedUserId)) ?? 'idle';
    final rawFailure = prefs.getString(
      _widgetRefreshFailureKey(normalizedUserId),
    );
    return ScheduleRefreshSnapshot(
      lastSuccessfulRefreshAt: DateTime.tryParse(rawTime ?? '')?.toLocal(),
      widgetState: ScheduleWidgetRefreshState.values.firstWhere(
        (value) => value.name == rawState,
        orElse: () => ScheduleWidgetRefreshState.idle,
      ),
      failure: ScheduleWidgetRefreshFailure.values
          .where((value) => value.name == rawFailure)
          .firstOrNull,
    );
  }

  static Future<void> markLoading(String userId) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _widgetRefreshStateKey(normalizedUserId),
      ScheduleWidgetRefreshState.loading.name,
    );
    await prefs.remove(_widgetRefreshFailureKey(normalizedUserId));
  }

  static Future<void> markSuccess(
    String userId, {
    DateTime? at,
    String? refreshId,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_matchesRefreshToken(prefs, normalizedUserId, refreshId)) return;
    await prefs.setString(
      _lastSuccessfulRefreshAtKey(normalizedUserId),
      (at ?? DateTime.now()).toIso8601String(),
    );
    await prefs.setString(
      _widgetRefreshStateKey(normalizedUserId),
      ScheduleWidgetRefreshState.idle.name,
    );
    await prefs.remove(_widgetRefreshFailureKey(normalizedUserId));
  }

  static Future<void> markFailure(
    String userId, {
    required ScheduleWidgetRefreshFailure failure,
    String? refreshId,
  }) async {
    final normalizedUserId = userId.trim();
    if (normalizedUserId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (!_matchesRefreshToken(prefs, normalizedUserId, refreshId)) return;
    await prefs.setString(
      _widgetRefreshStateKey(normalizedUserId),
      ScheduleWidgetRefreshState.failed.name,
    );
    await prefs.setString(
      _widgetRefreshFailureKey(normalizedUserId),
      failure.name,
    );
  }

  static bool _matchesRefreshToken(
    SharedPreferences prefs,
    String userId,
    String? refreshId,
  ) {
    final expected = (refreshId ?? '').trim();
    if (expected.isEmpty) return true;
    return prefs.getString(_widgetRefreshTokenKey(userId)) == expected;
  }

  static bool looksLikeCredentialFailure(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('credential') ||
        text.contains('凭证') ||
        text.contains('登录') ||
        text.contains('login') ||
        text.contains('unauthorized') ||
        text.contains('forbidden') ||
        text.contains('401') ||
        text.contains('403');
  }

  static DateTime? _migrateLegacyRefreshAt({
    required SharedPreferences prefs,
    required String userId,
  }) {
    if (userId.isEmpty) return null;
    final term =
        (prefs.getString('schedule_widget_term_$userId') ?? '')
            .trim()
            .isNotEmpty
        ? (prefs.getString('schedule_widget_term_$userId') ?? '').trim()
        : (prefs.getString('schedule_last_term_$userId') ?? '').trim();
    final week =
        (prefs.getString('schedule_widget_week_$userId') ?? '')
            .trim()
            .isNotEmpty
        ? (prefs.getString('schedule_widget_week_$userId') ?? '').trim()
        : (prefs.getString('schedule_last_week_$userId') ?? '').trim();
    if (term.isEmpty || week.isEmpty) return null;

    final rawSchedule = prefs.getString('schedule_${userId}_${term}_$week');
    if (!_isCachedScheduleValid(rawSchedule)) return null;

    final candidates = <DateTime>[];
    final fetchAt = prefs.getInt('schedule_fetch_at_${userId}_${term}_$week');
    if (fetchAt != null && fetchAt > 0) {
      candidates.add(DateTime.fromMillisecondsSinceEpoch(fetchAt));
    }
    final pollAt = DateTime.tryParse(
      prefs.getString('schedule_background_poll_last_success_at') ?? '',
    );
    if (pollAt != null) candidates.add(pollAt.toLocal());
    if (candidates.isEmpty) {
      return _cachedScheduleCoversToday(rawSchedule) ? DateTime.now() : null;
    }
    candidates.sort();
    return candidates.last;
  }

  static bool _isCachedScheduleValid(String? rawSchedule) {
    if (rawSchedule == null || rawSchedule.trim().isEmpty) return false;
    try {
      final decoded = json.decode(rawSchedule);
      return decoded is Map &&
          (decoded['weekDayList'] is List || decoded['eventList'] is List);
    } catch (_) {
      return false;
    }
  }

  static bool _cachedScheduleCoversToday(String? rawSchedule) {
    if (rawSchedule == null || rawSchedule.trim().isEmpty) return false;
    try {
      final decoded = json.decode(rawSchedule);
      if (decoded is! Map) return false;
      final weekDays = decoded['weekDayList'];
      if (weekDays is! List || weekDays.isEmpty) {
        final events = decoded['eventList'];
        return events is List && events.isNotEmpty;
      }
      final now = DateTime.now();
      for (final rawItem in weekDays) {
        if (rawItem is! Map) continue;
        if (rawItem['today'] == true) return true;
        final rawDate = (rawItem['weekDate'] ?? '').toString().trim();
        if (rawDate.isEmpty) return true;
        final numbers = RegExp(r'\d{1,4}')
            .allMatches(rawDate)
            .map((match) => int.tryParse(match.group(0) ?? ''))
            .whereType<int>()
            .toList(growable: false);
        if (numbers.length < 2) continue;
        final month = numbers.first >= 1000 && numbers.length >= 3
            ? numbers[1]
            : numbers[0];
        final day = numbers.first >= 1000 && numbers.length >= 3
            ? numbers[2]
            : numbers[1];
        if (month == now.month && day == now.day) return true;
      }
    } catch (_) {}
    return false;
  }
}
