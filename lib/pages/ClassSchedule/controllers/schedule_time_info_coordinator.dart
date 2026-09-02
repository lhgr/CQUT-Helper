import 'dart:convert';

import 'package:cqut_helper/api/course/course_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleTimeInfoCoordinator {
  final ScheduleApi service;
  final List<CampusTimeInfo>? Function() getTimeInfoList;
  final void Function(List<CampusTimeInfo> value) setTimeInfoList;
  final Future<void> Function()? onTimeInfoUpdated;
  static Future<bool>? _sharedRefreshInFlight;
  static String? _sharedCacheRaw;
  static _TimeInfoCacheSnapshot? _sharedCacheSnapshot;

  ScheduleTimeInfoCoordinator({
    required this.service,
    required this.getTimeInfoList,
    required this.setTimeInfoList,
    this.onTimeInfoUpdated,
  });

  static const String _prefsKeyTimeInfoCache = 'schedule_time_info_cache_v1';
  static const String _prefsKeyTimeInfoLastCampus =
      'schedule_time_info_last_campus';
  static const String _prefsKeyTimeInfoLastAttemptAt =
      'schedule_time_info_last_attempt_at';
  static const String _prefsKeyTimeInfoLastSuccessfulCheckAt =
      'schedule_time_info_last_successful_check_at';
  static const String _prefsKeyTimeInfoConsecutiveFailures =
      'schedule_time_info_consecutive_failures';
  static const int _freshnessIntervalMs = 12 * 60 * 60 * 1000;
  static const int _failureRetryCooldownMs = 5 * 60 * 1000;
  static const int _maxFailureRetryCooldownMs = 6 * 60 * 60 * 1000;
  static const int _forcedRefreshBurstCooldownMs = 2 * 1000;

  String _timeInfoFingerprint(List<CampusTimeInfo> list) {
    final items = list.map((e) => e.toJson()).toList();
    items.sort((a, b) {
      final sa = (a['sessionNum'] as int?) ?? 0;
      final sb = (b['sessionNum'] as int?) ?? 0;
      if (sa != sb) return sa.compareTo(sb);
      final aStart = (a['startTime'] ?? '').toString();
      final bStart = (b['startTime'] ?? '').toString();
      return aStart.compareTo(bStart);
    });
    return json.encode(items);
  }

  Future<bool> loadTimeInfoFromCacheIfAny() async {
    if (getTimeInfoList() != null) return true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyTimeInfoCache);
    if (raw == null || raw.trim().isEmpty) return false;
    final sharedSnapshot = _sharedCacheSnapshot;
    if (_sharedCacheRaw == raw && sharedSnapshot != null) {
      setTimeInfoList(List<CampusTimeInfo>.from(sharedSnapshot.items));
      return true;
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final items = decoded['items'];
      if (items is! List) return false;
      final list = <CampusTimeInfo>[];
      for (final item in items) {
        if (item is Map<String, dynamic>) {
          list.add(CampusTimeInfo.fromJson(item));
        } else if (item is Map) {
          list.add(CampusTimeInfo.fromJson(item.cast<String, dynamic>()));
        }
      }
      if (list.isEmpty) return false;
      final snapshot = _TimeInfoCacheSnapshot(
        items: List<CampusTimeInfo>.unmodifiable(list),
        campusName: decoded['campusName']?.toString(),
        updatedAt: decoded['updatedAt'],
      );
      _sharedCacheRaw = raw;
      _sharedCacheSnapshot = snapshot;
      setTimeInfoList(List<CampusTimeInfo>.from(snapshot.items));
      AppLogger.I.info(
        'TimeInfo',
        'cache_loaded',
        fields: {
          'count': list.length,
          'campus': snapshot.campusName,
          'updatedAt': snapshot.updatedAt,
        },
      );
      return true;
    } catch (e, st) {
      AppLogger.I.event(
        LogLevel.warn,
        'TimeInfo',
        event: 'schedule_time_info_cache_load_fail',
        messageZh: '从本地缓存读取节次信息失败',
        message: 'cache load failed',
        module: 'time_info',
        action: 'load_cache',
        status: 'fail',
        reason: 'cache_parse_failed',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  Future<bool> refreshTimeInfoIfEnabled({bool force = false}) async {
    final inFlight = _sharedRefreshInFlight;
    if (inFlight != null) {
      final changed = await inFlight;
      if (getTimeInfoList() == null) {
        await loadTimeInfoFromCacheIfAny();
      }
      return changed;
    }
    final future = _refreshTimeInfoIfEnabledInternal(force: force);
    _sharedRefreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_sharedRefreshInFlight, future)) {
        _sharedRefreshInFlight = null;
      }
    }
  }

  Future<bool> _refreshTimeInfoIfEnabledInternal({required bool force}) async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    String? campusName = prefs.getString(_prefsKeyTimeInfoLastCampus);
    if (campusName == null || campusName.trim().isEmpty) {
      try {
        campusName = await service.getCampusName();
      } catch (e, st) {
        AppLogger.I.event(
          LogLevel.warn,
          'TimeInfo',
          event: 'schedule_time_info_campus_resolve_fail',
          messageZh: '获取校区信息失败，使用默认校区',
          message: 'resolve campus failed',
          module: 'time_info',
          action: 'resolve_campus',
          status: 'fail',
          reason: 'campus_resolve_failed',
          error: e,
          stackTrace: st,
        );
      }
      if (campusName != null && campusName.trim().isNotEmpty) {
        await prefs.setString(_prefsKeyTimeInfoLastCampus, campusName);
      }
    }
    campusName ??= '两江校区';

    String? oldFp;
    int cachedUpdatedAt = 0;
    final cachedRaw = prefs.getString(_prefsKeyTimeInfoCache);
    if (cachedRaw != null && cachedRaw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(cachedRaw);
        if (decoded is Map<String, dynamic>) {
          oldFp = decoded['fingerprint']?.toString();
          cachedUpdatedAt = (decoded['updatedAt'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }

    final lastAttemptAt = prefs.getInt(_prefsKeyTimeInfoLastAttemptAt) ?? 0;
    final lastSuccessfulCheckAt =
        prefs.getInt(_prefsKeyTimeInfoLastSuccessfulCheckAt) ?? cachedUpdatedAt;
    final consecutiveFailures =
        prefs.getInt(_prefsKeyTimeInfoConsecutiveFailures) ?? 0;
    final failureRetryCooldown = failureRetryCooldownMs(consecutiveFailures);
    final sinceAttemptMs = nowMs - lastAttemptAt;
    final sinceSuccessfulCheckMs = nowMs - lastSuccessfulCheckAt;
    final hasCache = oldFp != null;
    final skipReason = force
        ? (lastAttemptAt > 0 && sinceAttemptMs < _forcedRefreshBurstCooldownMs
              ? 'forced_burst'
              : null)
        : (hasCache &&
                  lastSuccessfulCheckAt > 0 &&
                  sinceSuccessfulCheckMs < _freshnessIntervalMs
              ? 'cache_fresh'
              : (lastAttemptAt > lastSuccessfulCheckAt &&
                        sinceAttemptMs < failureRetryCooldown
                    ? 'recent_failure'
                    : null));
    if (skipReason != null) {
      AppLogger.I.info(
        'TimeInfo',
        'refresh_skipped',
        fields: {
          'reason': skipReason,
          'force': force,
          'hasCache': hasCache,
          'sinceAttemptMs': sinceAttemptMs,
          'sinceSuccessfulCheckMs': sinceSuccessfulCheckMs,
          'consecutiveFailures': consecutiveFailures,
          'failureRetryCooldownMs': failureRetryCooldown,
        },
      );
      return false;
    }
    await prefs.setInt(_prefsKeyTimeInfoLastAttemptAt, nowMs);

    AppLogger.I.info(
      'TimeInfo',
      'refresh_start',
      fields: {'campus': campusName, 'hasCache': hasCache, 'force': force},
    );
    List<CampusTimeInfo> fetched;
    try {
      fetched = await service.fetchCampusTimeInfo(campusName);
    } catch (e, st) {
      final failureCount = consecutiveFailures + 1;
      await prefs.setInt(_prefsKeyTimeInfoConsecutiveFailures, failureCount);
      final apiError = e is CourseApiException ? e : null;
      AppLogger.I.event(
        LogLevel.warn,
        'TimeInfo',
        event: 'schedule_time_info_refresh_fail',
        messageZh: '刷新校区节次信息失败',
        message: 'refresh failed',
        module: 'time_info',
        action: 'refresh',
        status: 'fail',
        reason: apiError?.kind.name ?? 'fetch_failed',
        error: e,
        stackTrace: st,
        fields: {
          'campus': campusName,
          'cacheAvailable': hasCache,
          if (cachedUpdatedAt > 0)
            'cacheAgeMs': (nowMs - cachedUpdatedAt).clamp(0, 1 << 62),
          'consecutiveFailures': failureCount,
          if (apiError?.statusCode != null) 'statusCode': apiError!.statusCode,
          if (apiError != null) ...apiError.diagnostics,
        },
      );
      return false;
    }
    if (fetched.isEmpty) {
      final failureCount = consecutiveFailures + 1;
      await prefs.setInt(_prefsKeyTimeInfoConsecutiveFailures, failureCount);
      AppLogger.I.event(
        LogLevel.warn,
        'TimeInfo',
        event: 'schedule_time_info_empty_response',
        messageZh: '校区节次信息为空，继续使用本地缓存',
        message: 'empty response; cache retained',
        module: 'time_info',
        action: 'refresh',
        status: 'fail',
        reason: 'empty_response',
        fields: {
          'campus': campusName,
          'cacheAvailable': hasCache,
          'consecutiveFailures': failureCount,
        },
      );
      return false;
    }

    await prefs.setInt(_prefsKeyTimeInfoConsecutiveFailures, 0);
    await prefs.setInt(_prefsKeyTimeInfoLastSuccessfulCheckAt, nowMs);

    final newFp = _timeInfoFingerprint(fetched);
    if (oldFp != null && oldFp == newFp) {
      if (getTimeInfoList() == null) {
        await loadTimeInfoFromCacheIfAny();
      }
      AppLogger.I.info(
        'TimeInfo',
        'refresh_unchanged',
        fields: {'campus': campusName, 'count': fetched.length},
      );
      return false;
    }

    setTimeInfoList(fetched);
    await prefs.setString(
      _prefsKeyTimeInfoCache,
      json.encode({
        'v': 1,
        'campusName': campusName,
        'fingerprint': newFp,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'items': fetched.map((e) => e.toJson()).toList(),
      }),
    );
    final notifyWidget = onTimeInfoUpdated;
    if (notifyWidget != null) {
      await notifyWidget();
    } else {
      await WidgetUpdater.updateTodayWidget(trigger: 'time_info_refresh');
    }
    final userId = prefs.getString('account')?.trim();
    if (userId != null && userId.isNotEmpty) {
      await CourseReminderScheduler.rescheduleForUser(userId);
    }
    AppLogger.I.info(
      'TimeInfo',
      'refresh_updated',
      fields: {'campus': campusName, 'count': fetched.length},
    );
    return true;
  }

  Future<void> ensureTimeInfoLoaded({
    required bool Function() isDisposed,
  }) async {
    if (isDisposed()) return;
    if (getTimeInfoList() != null) return;
    await loadTimeInfoFromCacheIfAny();
    await refreshTimeInfoIfEnabled();
  }

  static int failureRetryCooldownMs(int consecutiveFailures) {
    var cooldown = _failureRetryCooldownMs;
    for (var attempt = 1; attempt < consecutiveFailures; attempt++) {
      if (cooldown >= _maxFailureRetryCooldownMs) {
        return _maxFailureRetryCooldownMs;
      }
      cooldown *= 2;
    }
    return cooldown > _maxFailureRetryCooldownMs
        ? _maxFailureRetryCooldownMs
        : cooldown;
  }
}

class _TimeInfoCacheSnapshot {
  const _TimeInfoCacheSnapshot({
    required this.items,
    required this.campusName,
    required this.updatedAt,
  });

  final List<CampusTimeInfo> items;
  final String? campusName;
  final Object? updatedAt;
}
