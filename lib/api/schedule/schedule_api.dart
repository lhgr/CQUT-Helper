import 'dart:convert';
import 'package:cqut/api/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/utils/widget_updater.dart';

class ScheduleApi {
  final ApiService _apiService = ApiService();

  String _lastViewedWeekKey(String userId) => 'schedule_last_week_$userId';
  String _lastViewedTermKey(String userId) => 'schedule_last_term_$userId';
  String _scheduleKey(String userId, String yearTerm, String weekNum) =>
      'schedule_${userId}_${yearTerm}_$weekNum';

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
      weekNum = lastWeek;
      yearTerm = lastTerm;
    }

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
  }) async {
    final jsonMap = await _apiService.course.fetchWeekEvents(
      userId: userId,
      encryptedPassword: encryptedPassword,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );

    var data = ScheduleData.fromJson(jsonMap);

    // Save to SharedPreferences
    if (data.weekNum != null && data.yearTerm != null) {
      final prefs = await SharedPreferences.getInstance();
      final key = _scheduleKey(userId, data.yearTerm!, data.weekNum!);
      await prefs.setString(key, json.encode(jsonMap));

      await prefs.setString(_lastViewedWeekKey(userId), data.weekNum!);
      await prefs.setString(_lastViewedTermKey(userId), data.yearTerm!);
      await WidgetUpdater.updateTodayWidget();
    }

    return data;
  }

  Future<Map<String, dynamic>?> fetchRawWeekEvents({
    required String userId,
    required String encryptedPassword,
    required String weekNum,
    required String yearTerm,
  }) async {
    try {
      return await _apiService.course.fetchWeekEvents(
        userId: userId,
        encryptedPassword: encryptedPassword,
        weekNum: weekNum,
        yearTerm: yearTerm,
      );
    } catch (_) {
      return null;
    }
  }

  Future<String?> getCachedScheduleJson({
    required String userId,
    required String yearTerm,
    required String weekNum,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _scheduleKey(userId, yearTerm, weekNum);
    return prefs.getString(key);
  }
  
  Future<void> saveScheduleJson({
      required String userId,
      required String yearTerm,
      required String weekNum,
      required String jsonStr,
  }) async {
      final prefs = await SharedPreferences.getInstance();
      final key = _scheduleKey(userId, yearTerm, weekNum);
      await prefs.setString(key, jsonStr);
  }
}
