import 'dart:convert';
import 'package:cqut_helper/api/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:cqut_helper/utils/widget_updater.dart';

class ScheduleApi {
  final ApiService _apiService = ApiService();

  String _norm(String? s) => (s ?? '').trim();

  String _lastViewedWeekKey(String userId) => 'schedule_last_week_$userId';
  String _lastViewedTermKey(String userId) => 'schedule_last_term_$userId';
  String _widgetWeekKey(String userId) => 'schedule_widget_week_$userId';
  String _widgetTermKey(String userId) => 'schedule_widget_term_$userId';
  String _scheduleKey(String userId, String yearTerm, String weekNum) =>
      'schedule_${userId}_${_norm(yearTerm)}_${_norm(weekNum)}';

  Future<ScheduleData?> loadFromCache({
    required String userId,
    String? weekNum,
    String? yearTerm,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    if (weekNum == null || yearTerm == null) {
      final lastWeek = prefs.getString(_lastViewedWeekKey(userId));
      final lastTerm = prefs.getString(_lastViewedTermKey(userId));
      if (lastWeek == null || lastTerm == null) return null;
      weekNum = _norm(lastWeek);
      yearTerm = _norm(lastTerm);
    }

    weekNum = _norm(weekNum);
    yearTerm = _norm(yearTerm);
    final key = _scheduleKey(userId, yearTerm, weekNum);
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

  Future<ScheduleData> loadFromNetwork({
    required String userId,
    required String encryptedPassword,
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
  }) async {
    final reqWeek = _norm(weekNum);
    final reqTerm = _norm(yearTerm);
    final jsonMap = await _apiService.course.fetchWeekEvents(
      userId: userId,
      encryptedPassword: encryptedPassword,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );

    if (reqWeek.isNotEmpty) {
      final raw = (jsonMap['weekNum'] ?? '').toString().trim();
      if (raw.isEmpty) jsonMap['weekNum'] = reqWeek;
    }
    if (reqTerm.isNotEmpty) {
      final raw = (jsonMap['yearTerm'] ?? '').toString().trim();
      if (raw.isEmpty) jsonMap['yearTerm'] = reqTerm;
    }

    final data = ScheduleData.fromJson(jsonMap);

    // Save to SharedPreferences
    final dataWeek = _norm(data.weekNum);
    final dataTerm = _norm(data.yearTerm);
    final saveWeek = dataWeek.isNotEmpty ? dataWeek : reqWeek;
    final saveTerm = dataTerm.isNotEmpty ? dataTerm : reqTerm;
    if (saveWeek.isNotEmpty && saveTerm.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final key = _scheduleKey(userId, saveTerm, saveWeek);
      await prefs.setString(key, json.encode(jsonMap));

      if (persistLastViewed) {
        await prefs.setString(_lastViewedWeekKey(userId), saveWeek);
        await prefs.setString(_lastViewedTermKey(userId), saveTerm);
      }
      if (updateWidgetPins) {
        await prefs.setString(_widgetWeekKey(userId), saveWeek);
        await prefs.setString(_widgetTermKey(userId), saveTerm);
        await WidgetUpdater.updateTodayWidget();
      }
    }

    return data;
  }

  Future<Map<String, dynamic>> fetchRawWeekEvents({
    required String userId,
    required String encryptedPassword,
    required String weekNum,
    required String yearTerm,
  }) async {
    return await _apiService.course.fetchWeekEvents(
      userId: userId,
      encryptedPassword: encryptedPassword,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );
  }

  Future<List<CampusTimeInfo>> fetchCampusTimeInfo(String campusName) async {
    final list = await _apiService.course.fetchCampusTimeInfo(campusName);
    return list.map((e) => CampusTimeInfo.fromJson(e)).toList();
  }

  Future<ScheduleNoticePollData> fetchTermScheduleNotices({
    required String userId,
    required String encryptedPassword,
    required String yearTerm,
    String envName = 'prod',
    bool headless = true,
  }) async {
    return await _apiService.notice.fetchTermScheduleNotices(
      username: userId,
      encryptedPassword: encryptedPassword,
      yearTerm: yearTerm,
      env: envName,
      headless: headless,
    );
  }

  Future<String?> getCampusName() async {
    try {
      final info = await _apiService.user.getUserInfo();
      if (info['userCustomSetting'] != null &&
          info['userCustomSetting']['campusName'] != null) {
        return info['userCustomSetting']['campusName'];
      }
    } catch (_) {}
    return null;
  }

  Future<String?> getCachedScheduleJson({
    required String userId,
    required String yearTerm,
    required String weekNum,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scheduleKey(userId, _norm(yearTerm), _norm(weekNum));
    return prefs.getString(key);
  }

  Future<void> saveScheduleJson({
    required String userId,
    required String yearTerm,
    required String weekNum,
    required String jsonStr,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scheduleKey(userId, _norm(yearTerm), _norm(weekNum));
    await prefs.setString(key, jsonStr);
  }
}
