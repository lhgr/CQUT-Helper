import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/model/schedule_week_change.dart';
import 'package:cqut/api/schedule/schedule_api.dart';
import 'package:cqut/utils/app_logger.dart';
import 'package:cqut/utils/retry_utils.dart';
import 'package:cqut/utils/schedule_diff_utils.dart';
import 'package:cqut/utils/schedule_date.dart';
import 'package:cqut/utils/schedule_fingerprint_utils.dart';
import 'package:cqut/utils/schedule_update_log.dart';

class ScheduleController {
  final ScheduleApi _service;

  ScheduleController({ScheduleApi? service}) : _service = service ?? ScheduleApi();

  static const String _prefsKeyTimeInfoCache = 'schedule_time_info_cache_v1';
  static const String _prefsKeyTimeInfoLastCampus =
      'schedule_time_info_last_campus';
  static const int _timeInfoRefreshCooldownMs = 60 * 1000;

  // 状态数据
  Map<int, ScheduleData> weekCache = {};
  List<CampusTimeInfo>? timeInfoList;
  String? currentTerm;
  List<String>? weekList;
  String? actualCurrentWeekStr;
  String? actualCurrentTermStr;
  bool? nowInTeachingWeek;
  String? nowStatusLabel;

  // 凭证
  String? _userId;
  String? _encryptedPassword;

  // 预取定时器
  Timer? _prefetchTimer;
  bool _disposed = false;
  Future<bool>? _timeInfoRefreshInFlight;
  int _lastTimeInfoRefreshAtMs = 0;

  void dispose() {
    _disposed = true;
    _prefetchTimer?.cancel();
  }

  void reset() {
    weekCache.clear();
    currentTerm = null;
    weekList = null;
    actualCurrentWeekStr = null;
    actualCurrentTermStr = null;
    nowInTeachingWeek = null;
    nowStatusLabel = null;
    _prefetchTimer?.cancel();
  }

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('account');
    _encryptedPassword = prefs.getString('encrypted_password');
  }

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
    if (timeInfoList != null) return true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyTimeInfoCache);
    if (raw == null || raw.trim().isEmpty) return false;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return false;
      final items = decoded['items'];
      if (items is! List) return false;
      final list = <CampusTimeInfo>[];
      for (final it in items) {
        if (it is Map<String, dynamic>) {
          list.add(CampusTimeInfo.fromJson(it));
        } else if (it is Map) {
          list.add(CampusTimeInfo.fromJson(it.cast<String, dynamic>()));
        }
      }
      if (list.isEmpty) return false;
      timeInfoList = list;
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
    } catch (_) {
      return false;
    }
  }

  Future<bool> refreshTimeInfoIfEnabled({bool force = false}) async {
    final inFlight = _timeInfoRefreshInFlight;
    if (inFlight != null) return await inFlight;
    final future = _refreshTimeInfoIfEnabledInternal(force: force);
    _timeInfoRefreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_timeInfoRefreshInFlight, future)) {
        _timeInfoRefreshInFlight = null;
      }
    }
  }

  Future<bool> _refreshTimeInfoIfEnabledInternal({required bool force}) async {
    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (!force &&
        _lastTimeInfoRefreshAtMs > 0 &&
        nowMs - _lastTimeInfoRefreshAtMs < _timeInfoRefreshCooldownMs) {
      AppLogger.I.info(
        'TimeInfo',
        'refresh_skipped_cooldown',
        fields: {
          'cooldownMs': _timeInfoRefreshCooldownMs,
          'sinceMs': nowMs - _lastTimeInfoRefreshAtMs,
        },
      );
      return false;
    }
    _lastTimeInfoRefreshAtMs = nowMs;

    String? campusName = prefs.getString(_prefsKeyTimeInfoLastCampus);
    if (campusName == null || campusName.trim().isEmpty) {
      try {
        campusName = await _service.getCampusName();
      } catch (_) {}
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
    List<CampusTimeInfo>? fetched;
    try {
      fetched = await _service.fetchCampusTimeInfo(campusName);
    } catch (_) {
      AppLogger.I.warn('TimeInfo', 'refresh_failed');
      return false;
    }
    if (fetched.isEmpty) return false;

    final newFp = _timeInfoFingerprint(fetched);
    if (oldFp != null && oldFp == newFp) {
      if (timeInfoList == null) {
        await loadTimeInfoFromCacheIfAny();
      }
      AppLogger.I.info(
        'TimeInfo',
        'refresh_unchanged',
        fields: {'campus': campusName, 'count': fetched.length},
      );
      return false;
    }

    timeInfoList = fetched;
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

  Future<void> ensureTimeInfoLoaded() async {
    if (_disposed) return;
    if (timeInfoList != null) return;
    await loadTimeInfoFromCacheIfAny();
    await refreshTimeInfoIfEnabled();
  }

  /// 从缓存加载数据
  Future<ScheduleData?> loadFromCache({
    String? weekNum,
    String? yearTerm,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _userId ??= prefs.getString('account');

    final userId = _userId;
    if (userId == null || userId.isEmpty) return null;

    return _service.loadFromCache(
      userId: userId,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );
  }

  /// 从网络加载数据
  Future<ScheduleData> loadFromNetwork({
    String? weekNum,
    String? yearTerm,
  }) async {
    await _loadCredentials();

    if (_userId == null || _userId!.isEmpty) {
      throw Exception("未登录");
    }
    if (_encryptedPassword == null || _encryptedPassword!.isEmpty) {
      throw Exception("凭证已过期，请重新登录");
    }

    final data = await _service.loadFromNetwork(
      userId: _userId!,
      encryptedPassword: _encryptedPassword!,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );

    if (weekNum == null && yearTerm == null) {
      final now = DateTime.now();
      if (ScheduleDate.dataCoversDate(data, now)) {
        nowInTeachingWeek = true;
        nowStatusLabel = null;
        actualCurrentWeekStr = data.weekNum;
        actualCurrentTermStr = data.yearTerm;
      } else {
        nowInTeachingWeek = false;
        actualCurrentWeekStr = data.weekNum;
        actualCurrentTermStr = data.yearTerm;
      }
    }

    return data;
  }

  /// 处理加载的数据并更新缓存
  bool processLoadedData(ScheduleData data) {
    if (data.weekNum == null || data.weekList == null) return false;

    bool termChanged = false;
    if (currentTerm != data.yearTerm) {
      weekCache.clear();
      termChanged = true;
    }
    currentTerm = data.yearTerm;
    weekList = data.weekList;

    final weekNum = int.tryParse(data.weekNum!) ?? 1;
    weekCache[weekNum] = data;

    return termChanged;
  }

  /// 调度预取
  void schedulePrefetch(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(delay, () {
      _prefetchAdjacentWeeks(currentData, onUpdate);
    });
  }

  Future<void> _prefetchAdjacentWeeks(
    ScheduleData currentData,
    Function() onUpdate,
  ) async {
    final wList = currentData.weekList;
    final currentWeekStr = currentData.weekNum;
    final cTerm = currentData.yearTerm;

    if (wList == null || currentWeekStr == null || cTerm == null) return;

    final currentIndex = wList.indexOf(currentWeekStr);
    if (currentIndex == -1) return;

    if (_disposed) return;

    final futures = <Future<void>>[];

    // 预取上一周
    if (currentIndex > 0) {
      final prevWeek = wList[currentIndex - 1];
      futures.add(ensureWeekLoaded(prevWeek, cTerm));
    }
    // 预取下一周
    if (currentIndex < wList.length - 1) {
      final nextWeek = wList[currentIndex + 1];
      futures.add(ensureWeekLoaded(nextWeek, cTerm));
    }

    if (futures.isEmpty) return;
    await Future.wait(futures);
    onUpdate();
  }

  String _notifiedKey(String userId, String yearTerm, String weekNum) =>
      'schedule_notified_fp_${userId}_${yearTerm}_$weekNum';

  String _fingerprintKey(String userId, String yearTerm, String weekNum) =>
      'schedule_fp_${userId}_${yearTerm}_$weekNum';

  String _fingerprintUpdatedAtKey(String userId, String yearTerm, String weekNum) =>
      'schedule_fp_updated_at_${userId}_${yearTerm}_$weekNum';

  String _lastFetchAtKey(String userId, String yearTerm, String weekNum) =>
      'schedule_fetch_at_${userId}_${yearTerm}_$weekNum';

  Future<List<ScheduleWeekChange>> silentCheckRecentWeeksForChangesDetailed(
    ScheduleData currentData, {
    int weeksAhead = 1,
    int maxDiffLinesPerWeek = 30,
  }) async {
    final wList = currentData.weekList;
    final currentWeekStr = currentData.weekNum;
    final cTerm = currentData.yearTerm;
    if (wList == null || currentWeekStr == null || cTerm == null) return [];

    final currentIndex = wList.indexOf(currentWeekStr);
    if (currentIndex == -1) return [];

    await _loadCredentials();
    if (_userId == null || _userId!.isEmpty) return [];
    if (_encryptedPassword == null || _encryptedPassword!.isEmpty) return [];

    final prefs = await SharedPreferences.getInstance();
    final changed = <ScheduleWeekChange>[];

    final candidates = <String>[currentWeekStr];
    for (int offset = 1; offset <= weeksAhead; offset++) {
      final idx = currentIndex + offset;
      if (idx < 0 || idx >= wList.length) continue;
      candidates.add(wList[idx]);
    }

    for (final week in candidates) {
      if (_disposed) break;

      final beforeJsonStr = await _service.getCachedScheduleJson(
        userId: _userId!,
        yearTerm: cTerm,
        weekNum: week,
      );

      final fpKey = _fingerprintKey(_userId!, cTerm, week);
      final fpUpdatedAtKey = _fingerprintUpdatedAtKey(_userId!, cTerm, week);
      final fetchAtKey = _lastFetchAtKey(_userId!, cTerm, week);

      final lastFetchAt = prefs.getInt(fetchAtKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (lastFetchAt > 0 && nowMs - lastFetchAt < 5 * 60 * 1000) {
        continue;
      }

      Map<String, dynamic>? beforeJson;
      String? beforeFp = prefs.getString(fpKey);
      if (beforeFp == null && beforeJsonStr != null && beforeJsonStr.isNotEmpty) {
        try {
          final decoded = json.decode(beforeJsonStr);
          if (decoded is Map<String, dynamic>) {
            beforeJson = decoded;
            beforeFp = scheduleFingerprintFromWeekJsonMap(decoded);
            await prefs.setString(fpKey, beforeFp);
            await prefs.setInt(
              fpUpdatedAtKey,
              DateTime.now().millisecondsSinceEpoch,
            );
          }
        } catch (_) {}
      }

      Map<String, dynamic>? afterJson;
      Object? lastError;
      int lastAttempt = 0;
      try {
        afterJson = await retryWithExponentialBackoff<Map<String, dynamic>>(
          () => _service.fetchRawWeekEvents(
            userId: _userId!,
            encryptedPassword: _encryptedPassword!,
            weekNum: week,
            yearTerm: cTerm,
          ),
          maxAttempts: 3,
          onError: (attempt, error) {
            lastAttempt = attempt;
            lastError = error;
          },
        );
      } catch (_) {
        await ScheduleUpdateLog.appendFailure({
          'at': DateTime.now().millisecondsSinceEpoch,
          'scope': 'silent_check',
          'userId': _userId,
          'yearTerm': cTerm,
          'weekNum': week,
          'attempt': lastAttempt,
          'error': (lastError ?? 'unknown').toString(),
        });
        continue;
      }

      final afterFp = scheduleFingerprintFromWeekJsonMap(afterJson);
      await prefs.setInt(fetchAtKey, DateTime.now().millisecondsSinceEpoch);
      if (beforeFp != null && beforeFp == afterFp) continue;

      final afterData = ScheduleData.fromJson(afterJson);
      if (afterData.weekNum != null && afterData.yearTerm != null) {
        final afterStr = json.encode(afterJson);
        await _service.saveScheduleJson(
          userId: _userId!,
          yearTerm: cTerm,
          weekNum: week,
          jsonStr: afterStr,
        );
        await prefs.setString(fpKey, afterFp);
        await prefs.setInt(fpUpdatedAtKey, DateTime.now().millisecondsSinceEpoch);

        final wInt = int.tryParse(afterData.weekNum!) ?? 0;
        weekCache[wInt] = afterData;

        if (beforeJson != null) {
          final stats = diffWeekEventFingerprints(
            beforeJson: beforeJson,
            afterJson: afterJson,
          );
          await ScheduleUpdateLog.appendRun({
            'at': DateTime.now().millisecondsSinceEpoch,
            'type': 'week_update',
            'userId': _userId,
            'yearTerm': cTerm,
            'weekNum': week,
            'bytes': afterStr.length,
            'delta': {
              'added': stats.added,
              'removed': stats.removed,
              'changed': stats.changed,
              'same': stats.same,
            },
          });
        }
      }

      if (beforeFp == null) continue;

      final notifiedKey = _notifiedKey(_userId!, cTerm, week);
      final lastNotifiedFp = prefs.getString(notifiedKey);
      if (lastNotifiedFp == afterFp) continue;

      List<String> lines = const <String>[];
      try {
        if (beforeJson == null &&
            beforeJsonStr != null &&
            beforeJsonStr.isNotEmpty) {
          final decoded = json.decode(beforeJsonStr);
          if (decoded is Map<String, dynamic>) beforeJson = decoded;
        }

        ScheduleData? beforeData;
        if (beforeJson != null) {
          beforeData = ScheduleData.fromJson(beforeJson);
        } else {
          final wInt = int.tryParse(week) ?? 0;
          beforeData = weekCache[wInt];
        }

        if (beforeData != null) {
          lines = diffScheduleWeekLines(
            before: beforeData,
            after: afterData,
            maxLines: maxDiffLinesPerWeek,
          );
        }

        if (lines.isEmpty && beforeJson != null) {
          final stats = diffWeekEventFingerprints(
            beforeJson: beforeJson,
            afterJson: afterJson,
          );
          if (stats.added > 0 || stats.removed > 0 || stats.changed > 0) {
            lines = [
              '变更概览：新增${stats.added} 删除${stats.removed} 修改${stats.changed}',
            ];
          }
        }
      } catch (_) {}

      await prefs.setString(notifiedKey, afterFp);
      changed.add(ScheduleWeekChange(weekNum: week, lines: lines));
    }

    return changed;
  }

  void prefetchAllWeeksInBackground(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration interval = const Duration(milliseconds: 150),
    bool forceRefresh = false,
  }) {
    Future(() async {
      final wList = currentData.weekList;
      final currentWeekStr = currentData.weekNum;
      final cTerm = currentData.yearTerm;
      if (wList == null || currentWeekStr == null || cTerm == null) return;

      for (final week in wList) {
        if (_disposed) return;
        if (week == currentWeekStr) continue;
        await ensureWeekLoaded(week, cTerm, forceRefresh: forceRefresh);
        if (_disposed) return;
        onUpdate();
        if (interval > Duration.zero) {
          await Future.delayed(interval);
        }
      }
    });
  }

  Future<void> ensureWeekLoaded(
    String weekNum,
    String yearTerm, {
    bool forceRefresh = false,
  }) async {
    final wInt = int.tryParse(weekNum) ?? 0;

    if (!forceRefresh) {
      if (weekCache.containsKey(wInt)) return;

      // 尝试读取磁盘缓存
      final cached = await loadFromCache(weekNum: weekNum, yearTerm: yearTerm);
      if (cached != null) {
        weekCache[wInt] = cached;
        return;
      }
    }

    try {
      final data = await loadFromNetwork(weekNum: weekNum, yearTerm: yearTerm);
      processLoadedData(data);
      final uid = _userId;
      final term = (data.yearTerm ?? yearTerm).trim();
      final week = (data.weekNum ?? weekNum).trim();
      if (uid != null && uid.isNotEmpty && term.isNotEmpty && week.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final fpKey = _fingerprintKey(uid, term, week);
        final fpUpdatedAtKey = _fingerprintUpdatedAtKey(uid, term, week);
        final fetchAtKey = _lastFetchAtKey(uid, term, week);
        final now = DateTime.now().millisecondsSinceEpoch;
        final fp = scheduleFingerprintFromScheduleData(data);
        await prefs.setString(fpKey, fp);
        await prefs.setInt(fpUpdatedAtKey, now);
        await prefs.setInt(fetchAtKey, now);
      }
    } catch (e) {
      // 预取或刷新失败忽略
    }
  }
}
