import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/class_schedule_model.dart';
import '../models/schedule_week_change.dart';
import '../services/schedule_service.dart';
import '../utils/schedule_diff_utils.dart';
import '../../../utils/schedule_date.dart';

class ScheduleController {
  final ScheduleService _service = ScheduleService();

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
      'schedule_notified_${userId}_${yearTerm}_$weekNum';

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

      final before = await _service.getCachedScheduleJson(
        userId: _userId!,
        yearTerm: cTerm,
        weekNum: week,
      );

      final jsonMap = await _service.fetchRawWeekEvents(
        userId: _userId!,
        encryptedPassword: _encryptedPassword!,
        weekNum: week,
        yearTerm: cTerm,
      );

      if (jsonMap == null) continue;

      final after = json.encode(jsonMap);
      final afterData = ScheduleData.fromJson(jsonMap);
      if (afterData.weekNum != null && afterData.yearTerm != null) {
        await _service.saveScheduleJson(
          userId: _userId!,
          yearTerm: cTerm,
          weekNum: week,
          jsonStr: after,
        );
        final wInt = int.tryParse(afterData.weekNum!) ?? 0;
        weekCache[wInt] = afterData;
      }

      if (before == null || before == after) continue;

      final notifiedKey = _notifiedKey(_userId!, cTerm, week);
      final lastNotified = prefs.getString(notifiedKey);
      if (lastNotified == after) continue;

      List<String> lines = const <String>[];
      try {
        final decoded = json.decode(before);
        if (decoded is Map<String, dynamic>) {
          final beforeData = ScheduleData.fromJson(decoded);
          lines = diffScheduleWeekLines(
            before: beforeData,
            after: afterData,
            maxLines: maxDiffLinesPerWeek,
          );
        }
      } catch (_) {}

      await prefs.setString(notifiedKey, after);
      changed.add(ScheduleWeekChange(weekNum: week, lines: lines));
    }

    return changed;
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
