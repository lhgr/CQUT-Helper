import 'dart:async';
import 'dart:convert';
import 'package:cqut/api/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../model/schedule_model.dart';
import '../../utils/schedule_date.dart';

class ScheduleController {
  final ApiService _apiService = ApiService();

  // 状态数据
  Map<int, ScheduleData> weekCache = {};
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

  void dispose() {
    _disposed = true;
    _prefetchTimer?.cancel();
  }

  Future<void> _loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('account');
    _encryptedPassword = prefs.getString('encrypted_password');
  }

  String _lastViewedWeekKey(String userId) => 'schedule_last_week_$userId';
  String _lastViewedTermKey(String userId) => 'schedule_last_term_$userId';

  /// 从缓存加载数据
  Future<ScheduleData?> loadFromCache({
    String? weekNum,
    String? yearTerm,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _userId ??= prefs.getString('account');

    final userId = _userId;
    if (userId == null || userId.isEmpty) return null;

    if (weekNum == null || yearTerm == null) {
      final lastWeek = prefs.getString(_lastViewedWeekKey(userId));
      final lastTerm = prefs.getString(_lastViewedTermKey(userId));
      if (lastWeek == null || lastTerm == null) return null;
      weekNum = lastWeek;
      yearTerm = lastTerm;
    }

    final key = 'schedule_${userId}_${yearTerm}_$weekNum';
    final jsonStr = prefs.getString(key);
    if (jsonStr == null) return null;

    try {
      final decoded = json.decode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return ScheduleData.fromJson(decoded);
      }
    } catch (_) {}

    return null;
  }

  /// 从网络加载数据
  /// 返回加载的 ScheduleData
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

    final jsonMap = await _apiService.course.fetchWeekEvents(
      userId: _userId!,
      encryptedPassword: _encryptedPassword!,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );

    var data = ScheduleData.fromJson(jsonMap);

    // 保存到 SharedPreferences
    if (data.weekNum != null && data.yearTerm != null) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'schedule_${_userId}_${data.yearTerm}_${data.weekNum}';
      await prefs.setString(key, json.encode(jsonMap));

      await prefs.setString(_lastViewedWeekKey(_userId!), data.weekNum!);
      await prefs.setString(_lastViewedTermKey(_userId!), data.yearTerm!);
    }

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
  /// 返回是否需要更新 UI (例如 currentTerm 改变)
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

  Future<List<String>> silentCheckUpcomingWeeksForChanges(
    ScheduleData currentData, {
    int weeksAhead = 3,
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
    final changedWeeks = <String>[];

    for (int offset = 1; offset <= weeksAhead; offset++) {
      if (_disposed) break;
      final idx = currentIndex + offset;
      if (idx < 0 || idx >= wList.length) continue;
      final week = wList[idx];

      final cacheKey = 'schedule_${_userId}_${cTerm}_$week';
      final before = prefs.getString(cacheKey);

      Map<String, dynamic> jsonMap;
      try {
        jsonMap = await _apiService.course.fetchWeekEvents(
          userId: _userId!,
          encryptedPassword: _encryptedPassword!,
          weekNum: week,
          yearTerm: cTerm,
        );
      } catch (_) {
        continue;
      }

      final after = json.encode(jsonMap);
      if (before != null && before != after) {
        changedWeeks.add(week);
      }

      final data = ScheduleData.fromJson(jsonMap);
      if (data.weekNum != null && data.yearTerm != null) {
        await prefs.setString(cacheKey, after);
        final wInt = int.tryParse(data.weekNum!) ?? 0;
        weekCache[wInt] = data;
      }
    }

    return changedWeeks;
  }

  String _notifiedKey(String userId, String yearTerm, String weekNum) =>
      'schedule_notified_${userId}_${yearTerm}_$weekNum';

  Future<List<String>> silentCheckRecentWeeksForChanges(
    ScheduleData currentData, {
    int weeksAhead = 1,
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
    final changedWeeks = <String>[];

    final candidates = <String>[currentWeekStr];
    for (int offset = 1; offset <= weeksAhead; offset++) {
      final idx = currentIndex + offset;
      if (idx < 0 || idx >= wList.length) continue;
      candidates.add(wList[idx]);
    }

    for (final week in candidates) {
      if (_disposed) break;

      final cacheKey = 'schedule_${_userId}_${cTerm}_$week';
      final before = prefs.getString(cacheKey);

      Map<String, dynamic> jsonMap;
      try {
        jsonMap = await _apiService.course.fetchWeekEvents(
          userId: _userId!,
          encryptedPassword: _encryptedPassword!,
          weekNum: week,
          yearTerm: cTerm,
        );
      } catch (_) {
        continue;
      }

      final after = json.encode(jsonMap);

      final data = ScheduleData.fromJson(jsonMap);
      if (data.weekNum != null && data.yearTerm != null) {
        await prefs.setString(cacheKey, after);
        final wInt = int.tryParse(data.weekNum!) ?? 0;
        weekCache[wInt] = data;
      }

      if (before == null || before == after) continue;

      final notifiedKey = _notifiedKey(_userId!, cTerm, week);
      final lastNotified = prefs.getString(notifiedKey);
      if (lastNotified == after) continue;

      await prefs.setString(notifiedKey, after);
      changedWeeks.add(week);
    }

    return changedWeeks;
  }

  void prefetchAllWeeksInBackground(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration interval = const Duration(milliseconds: 150),
  }) {
    Future(() async {
      final wList = currentData.weekList;
      final currentWeekStr = currentData.weekNum;
      final cTerm = currentData.yearTerm;
      if (wList == null || currentWeekStr == null || cTerm == null) return;

      for (final week in wList) {
        if (_disposed) return;
        if (week == currentWeekStr) continue;
        await ensureWeekLoaded(week, cTerm);
        if (_disposed) return;
        onUpdate();
        if (interval > Duration.zero) {
          await Future.delayed(interval);
        }
      }
    });
  }

  /// 静默更新相邻周（强制刷新）
  Future<void> silentUpdateAdjacentWeeks(
    ScheduleData currentData,
    Function() onUpdate,
  ) async {
    final wList = currentData.weekList;
    final currentWeekStr = currentData.weekNum;
    final cTerm = currentData.yearTerm;

    if (wList == null || currentWeekStr == null || cTerm == null) return;

    final currentIndex = wList.indexOf(currentWeekStr);
    if (currentIndex == -1) return;

    final futures = <Future>[];

    // 强制刷新上一周
    if (currentIndex > 0) {
      final prevWeek = wList[currentIndex - 1];
      futures.add(ensureWeekLoaded(prevWeek, cTerm, forceRefresh: true));
    }
    // 强制刷新下一周
    if (currentIndex < wList.length - 1) {
      final nextWeek = wList[currentIndex + 1];
      futures.add(ensureWeekLoaded(nextWeek, cTerm, forceRefresh: true));
    }

    if (futures.isNotEmpty) {
      await Future.wait(futures);
      onUpdate();
    }
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
    } catch (e) {
      // 预取或刷新失败忽略
    }
  }
}
