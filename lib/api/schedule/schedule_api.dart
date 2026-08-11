import 'dart:convert';
import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/api/course/course_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/widget_updater.dart';

class ScheduleApi {
  final ApiService _apiService = ApiService();
  final CourseApi _courseApi;

  ScheduleApi({CourseApi? courseApi})
    : _courseApi = courseApi ?? ApiService().course;

  String _norm(String? s) => (s ?? '').trim();

  String _lastViewedWeekKey(String userId) => 'schedule_last_week_$userId';
  String _lastViewedTermKey(String userId) => 'schedule_last_term_$userId';
  String _widgetWeekKey(String userId) => 'schedule_widget_week_$userId';
  String _widgetTermKey(String userId) => 'schedule_widget_term_$userId';
  String _scheduleKey(String userId, String yearTerm, String weekNum) =>
      'schedule_${userId}_${_norm(yearTerm)}_${_norm(weekNum)}';
  String _rawScheduleKey(String userId, String yearTerm, String weekNum) =>
      'schedule_remote_${userId}_${_norm(yearTerm)}_${_norm(weekNum)}';

  static String lastFetchAtKey(
    String userId,
    String yearTerm,
    String weekNum,
  ) =>
      'schedule_fetch_at_${userId.trim()}_${yearTerm.trim()}_${weekNum.trim()}';

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
    final rawKey = _rawScheduleKey(userId, yearTerm, weekNum);
    final displayKey = _scheduleKey(userId, yearTerm, weekNum);
    final jsonStr = prefs.getString(rawKey) ?? prefs.getString(displayKey);
    if (jsonStr == null) return null;

    try {
      final decoded = json.decode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        final source = ScheduleData.fromJson(decoded);
        final merged = await ScheduleCustomizationManager.instance
            .applyToSchedule(userId: userId, schedule: source);
        await prefs.setString(displayKey, json.encode(merged.toJson()));
        if (!prefs.containsKey(rawKey)) {
          await prefs.setString(rawKey, jsonStr);
        }
        return merged;
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
    bool notifyWidget = true,
    String? refreshId,
  }) async {
    final reqWeek = _norm(weekNum);
    final reqTerm = _norm(yearTerm);
    final jsonMap = await _courseApi.fetchWeekEvents(
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
      final rawKey = _rawScheduleKey(userId, saveTerm, saveWeek);
      final displayKey = _scheduleKey(userId, saveTerm, saveWeek);
      await prefs.setString(rawKey, json.encode(jsonMap));
      final merged = await ScheduleCustomizationManager.instance
          .applyToSchedule(userId: userId, schedule: data);
      await prefs.setString(displayKey, json.encode(merged.toJson()));

      if (persistLastViewed) {
        await prefs.setString(_lastViewedWeekKey(userId), saveWeek);
        await prefs.setString(_lastViewedTermKey(userId), saveTerm);
      }
      if (updateWidgetPins) {
        await prefs.setString(_widgetWeekKey(userId), saveWeek);
        await prefs.setString(_widgetTermKey(userId), saveTerm);
      }
      await ScheduleRefreshState.markSuccess(userId, refreshId: refreshId);
      await prefs.setInt(
        lastFetchAtKey(userId, saveTerm, saveWeek),
        DateTime.now().millisecondsSinceEpoch,
      );
      final widgetWeek = prefs.getString(_widgetWeekKey(userId))?.trim();
      final widgetTerm = prefs.getString(_widgetTermKey(userId))?.trim();
      final updatesCurrentDisplay =
          updateWidgetPins ||
          (widgetWeek == saveWeek && widgetTerm == saveTerm);
      if (updatesCurrentDisplay) {
        if (notifyWidget) {
          await WidgetUpdater.updateTodayWidget(trigger: 'schedule_refresh');
        }
        await _rescheduleCourseRemindersSafely(userId);
      }
    }

    return await ScheduleCustomizationManager.instance.applyToSchedule(
      userId: userId,
      schedule: data,
    );
  }

  Future<Map<String, dynamic>> fetchRawWeekEvents({
    required String userId,
    required String encryptedPassword,
    required String weekNum,
    required String yearTerm,
  }) async {
    return await _courseApi.fetchWeekEvents(
      userId: userId,
      encryptedPassword: encryptedPassword,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );
  }

  Future<List<EventItem>> fetchCustomEvents({
    required String userId,
    required String encryptedPassword,
    required String yearTerm,
    required Iterable<int> weeks,
    void Function(int completed, int total)? onProgress,
  }) async {
    final weekList = weeks.toSet().toList(growable: false)..sort();
    final byId = <String, EventItem>{};
    for (var index = 0; index < weekList.length; index++) {
      final response = await fetchRawWeekEvents(
        userId: userId,
        encryptedPassword: encryptedPassword,
        weekNum: weekList[index].toString(),
        yearTerm: yearTerm,
      );
      final events = response['eventList'];
      if (events is List) {
        for (final raw in events) {
          if (raw is! Map) continue;
          final event = EventItem.fromJson(raw.cast<String, dynamic>());
          final eventId = (event.eventID ?? '').trim();
          if (event.eventType == '3' && eventId.isNotEmpty) {
            byId[eventId] = event;
          }
        }
      }
      onProgress?.call(index + 1, weekList.length);
    }
    final result = byId.values.toList(growable: false);
    result.sort((a, b) {
      final byDay = (int.tryParse(a.weekDay ?? '') ?? 8).compareTo(
        int.tryParse(b.weekDay ?? '') ?? 8,
      );
      if (byDay != 0) return byDay;
      final bySession = (int.tryParse(a.sessionStart ?? '') ?? 99).compareTo(
        int.tryParse(b.sessionStart ?? '') ?? 99,
      );
      if (bySession != 0) return bySession;
      return (a.eventName ?? '').compareTo(b.eventName ?? '');
    });
    return result;
  }

  Future<void> addCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String yearTerm,
    required List<int> weekList,
    required int weekDay,
    required int sessionStart,
    required int sessionCount,
    required String eventName,
    required String address,
    required String memberName,
  }) {
    return _courseApi.addCustomEvent(
      userId: userId,
      encryptedPassword: encryptedPassword,
      yearTerm: yearTerm,
      weekList: weekList,
      weekDay: weekDay,
      sessionStart: sessionStart,
      sessionCount: sessionCount,
      eventName: eventName,
      address: address,
      memberName: memberName,
    );
  }

  Future<void> editCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String eventId,
    required List<int> weekList,
    required int weekDay,
    required int sessionStart,
    required int sessionCount,
    required String eventName,
    required String address,
    required String memberName,
  }) {
    return _courseApi.editCustomEvent(
      userId: userId,
      encryptedPassword: encryptedPassword,
      eventId: eventId,
      weekList: weekList,
      weekDay: weekDay,
      sessionStart: sessionStart,
      sessionCount: sessionCount,
      eventName: eventName,
      address: address,
      memberName: memberName,
    );
  }

  Future<void> deleteCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String eventId,
  }) {
    return _courseApi.deleteCustomEvent(
      userId: userId,
      encryptedPassword: encryptedPassword,
      eventId: eventId,
    );
  }

  Future<void> invalidateCachedWeeks({
    required String userId,
    required String yearTerm,
    required Iterable<int> weeks,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    for (final week in weeks.toSet()) {
      final weekNum = week.toString();
      await prefs.remove(_rawScheduleKey(userId, yearTerm, weekNum));
      await prefs.remove(_scheduleKey(userId, yearTerm, weekNum));
      await prefs.remove(lastFetchAtKey(userId, yearTerm, weekNum));
      await prefs.remove('schedule_fp_${userId}_${yearTerm}_$weekNum');
      await prefs.remove(
        'schedule_fp_updated_at_${userId}_${yearTerm}_$weekNum',
      );
    }
  }

  Future<List<CampusTimeInfo>> fetchCampusTimeInfo(String campusName) async {
    final list = await _courseApi.fetchCampusTimeInfo(campusName);
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
    final key = _rawScheduleKey(userId, _norm(yearTerm), _norm(weekNum));
    return prefs.getString(key) ??
        prefs.getString(_scheduleKey(userId, _norm(yearTerm), _norm(weekNum)));
  }

  Future<void> saveScheduleJson({
    required String userId,
    required String yearTerm,
    required String weekNum,
    required String jsonStr,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final rawKey = _rawScheduleKey(userId, _norm(yearTerm), _norm(weekNum));
    final displayKey = _scheduleKey(userId, _norm(yearTerm), _norm(weekNum));
    await prefs.setString(rawKey, jsonStr);
    final decoded = json.decode(jsonStr);
    if (decoded is Map<String, dynamic>) {
      final merged = await ScheduleCustomizationManager.instance
          .applyToSchedule(
            userId: userId,
            schedule: ScheduleData.fromJson(decoded),
          );
      await prefs.setString(displayKey, json.encode(merged.toJson()));
    }
    await ScheduleRefreshState.markSuccess(userId);
    await prefs.setInt(
      lastFetchAtKey(userId, _norm(yearTerm), _norm(weekNum)),
      DateTime.now().millisecondsSinceEpoch,
    );
    final widgetWeek = prefs.getString(_widgetWeekKey(userId))?.trim();
    final widgetTerm = prefs.getString(_widgetTermKey(userId))?.trim();
    if (widgetWeek == _norm(weekNum) && widgetTerm == _norm(yearTerm)) {
      await WidgetUpdater.updateTodayWidget(trigger: 'schedule_refresh');
      await _rescheduleCourseRemindersSafely(userId);
    }
  }

  Future<void> _rescheduleCourseRemindersSafely(String userId) async {
    try {
      await CourseReminderScheduler.rescheduleForUser(userId);
    } catch (error, stackTrace) {
      // The schedule has already been fetched and persisted. A notification
      // permission/plugin failure must not turn that successful refresh into a
      // misleading widget refresh failure.
      AppLogger.I.warn(
        'ScheduleApi',
        'course reminder reschedule failed after schedule refresh',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
