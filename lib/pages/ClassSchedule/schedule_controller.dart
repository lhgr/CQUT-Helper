import 'dart:async';
import 'dart:convert';
import 'package:cqut/api/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../model/schedule_model.dart';

class ScheduleController {
  final ApiService _apiService = ApiService();

  // 状态数据
  Map<int, ScheduleData> weekCache = {};
  String? currentTerm;
  List<String>? weekList;
  String? actualCurrentWeekStr;
  String? actualCurrentTermStr;

  // 凭证
  String? _userId;
  String? _encryptedPassword;

  // 预取定时器
  Timer? _prefetchTimer;

  void dispose() {
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
    if (_userId == null) {
      _userId = prefs.getString('account');
    }

    if (_userId == null || _userId!.isEmpty) return null;

    if (weekNum != null && yearTerm != null) {
      final key = 'schedule_${_userId}_${yearTerm}_$weekNum';
      final jsonStr = prefs.getString(key);
      if (jsonStr != null) {
        try {
          return ScheduleData.fromJson(json.decode(jsonStr));
        } catch (e) {
          print("Cache parse error: $e");
        }
      }
    }
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

    final data = ScheduleData.fromJson(jsonMap);

    // 保存到 SharedPreferences
    if (data.weekNum != null && data.yearTerm != null) {
      final prefs = await SharedPreferences.getInstance();
      final key = 'schedule_${_userId}_${data.yearTerm}_${data.weekNum}';
      await prefs.setString(key, json.encode(jsonMap));
    }

    // 更新实际当前周/学期
    if (weekNum == null && yearTerm == null) {
      if (data.weekNum != null) {
        actualCurrentWeekStr = data.weekNum;
      }
      if (data.yearTerm != null) {
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
  void schedulePrefetch(ScheduleData currentData, Function() onUpdate) {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(Duration(seconds: 2), () {
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

    // 预取上一周
    if (currentIndex > 0) {
      final prevWeek = wList[currentIndex - 1];
      await ensureWeekLoaded(prevWeek, cTerm);
      onUpdate();
    }
    // 预取下一周
    if (currentIndex < wList.length - 1) {
      final nextWeek = wList[currentIndex + 1];
      await ensureWeekLoaded(nextWeek, cTerm);
      onUpdate();
    }
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
