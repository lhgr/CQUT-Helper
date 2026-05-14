import 'dart:convert';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleTimeInfoCoordinator {
  final ScheduleApi service;
  final List<CampusTimeInfo>? Function() getTimeInfoList;
  final void Function(List<CampusTimeInfo> value) setTimeInfoList;
  Future<bool>? _refreshInFlight;
  int _lastRefreshAtMs = 0;

  ScheduleTimeInfoCoordinator({
    required this.service,
    required this.getTimeInfoList,
    required this.setTimeInfoList,
  });

  static const String _prefsKeyTimeInfoCache = 'schedule_time_info_cache_v1';
  static const String _prefsKeyTimeInfoLastCampus =
      'schedule_time_info_last_campus';
  static const int _refreshCooldownMs = 60 * 1000;

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
      setTimeInfoList(list);
      AppLogger.I.info(
        'TimeInfo',
        'cache_loaded',
        fields: {
          'count': list.length,
          'campus': decoded['campusName']?.toString(),
          'updatedAt': decoded['updatedAt'],
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
    final inFlight = _refreshInFlight;
    if (inFlight != null) return await inFlight;
    final future = _refreshTimeInfoIfEnabledInternal(force: force);
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _refreshTimeInfoIfEnabledInternal({required bool force}) async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        _lastRefreshAtMs > 0 &&
        nowMs - _lastRefreshAtMs < _refreshCooldownMs) {
      AppLogger.I.info(
        'TimeInfo',
        'refresh_skipped_cooldown',
        fields: {
          'cooldownMs': _refreshCooldownMs,
          'sinceMs': nowMs - _lastRefreshAtMs,
        },
      );
      return false;
    }
    _lastRefreshAtMs = nowMs;

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
    final cachedRaw = prefs.getString(_prefsKeyTimeInfoCache);
    if (cachedRaw != null && cachedRaw.trim().isNotEmpty) {
      try {
        final decoded = json.decode(cachedRaw);
        if (decoded is Map<String, dynamic>) {
          oldFp = decoded['fingerprint']?.toString();
        }
      } catch (_) {}
    }

    AppLogger.I.info(
      'TimeInfo',
      'refresh_start',
      fields: {
        'campus': campusName,
        'hasCache': oldFp != null,
        'force': force,
      },
    );
    List<CampusTimeInfo> fetched;
    try {
      fetched = await service.fetchCampusTimeInfo(campusName);
    } catch (e, st) {
      AppLogger.I.event(
        LogLevel.warn,
        'TimeInfo',
        event: 'schedule_time_info_refresh_fail',
        messageZh: '刷新校区节次信息失败',
        message: 'refresh failed',
        module: 'time_info',
        action: 'refresh',
        status: 'fail',
        reason: 'fetch_failed',
        error: e,
        stackTrace: st,
        fields: {'campus': campusName},
      );
      return false;
    }
    if (fetched.isEmpty) return false;

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
    AppLogger.I.info(
      'TimeInfo',
      'refresh_updated',
      fields: {'campus': campusName, 'count': fetched.length},
    );
    return true;
  }

  Future<void> ensureTimeInfoLoaded({required bool Function() isDisposed}) async {
    if (isDisposed()) return;
    if (getTimeInfoList() != null) return;
    await loadTimeInfoFromCacheIfAny();
    await refreshTimeInfoIfEnabled();
  }
}
