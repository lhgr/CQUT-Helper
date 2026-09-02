import 'dart:convert';
import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/api/course/course_api.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:cqut_helper/manager/schedule_refresh_state.dart';
import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_cache_database.dart';
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
    final entry = await ScheduleCacheDatabase.instance.load(
      userId: userId,
      yearTerm: yearTerm,
      weekNum: weekNum,
    );
    if (entry == null) return null;

    try {
      final decoded = json.decode(entry.rawJson);
      if (decoded is Map<String, dynamic>) {
        final source = ScheduleData.fromJson(decoded);
        final merged = await ScheduleCustomizationManager.instance
            .applyToSchedule(userId: userId, schedule: source);
        final updatesVisibleWidgetProjection =
            await _writeWidgetProjectionIfPinned(
              prefs: prefs,
              userId: userId,
              yearTerm: yearTerm,
              weekNum: weekNum,
              schedule: merged,
            );
        if (updatesVisibleWidgetProjection) {
          await WidgetUpdater.updateTodayWidget(trigger: 'schedule_refresh');
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

    final dataWeek = _norm(data.weekNum);
    final dataTerm = _norm(data.yearTerm);
    final saveWeek = dataWeek.isNotEmpty ? dataWeek : reqWeek;
    final saveTerm = dataTerm.isNotEmpty ? dataTerm : reqTerm;
    if (saveWeek.isNotEmpty && saveTerm.isNotEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final oldWidgetWeek = _effectiveWidgetWeek(prefs, userId);
      final oldWidgetTerm = _effectiveWidgetTerm(prefs, userId);
      final fetchedAt = DateTime.now();
      await ScheduleCacheDatabase.instance.upsert(
        userId: userId,
        yearTerm: saveTerm,
        weekNum: saveWeek,
        rawJson: json.encode(jsonMap),
        fetchedAt: fetchedAt,
      );
      final merged = await ScheduleCustomizationManager.instance
          .applyToSchedule(userId: userId, schedule: data);

      if (persistLastViewed) {
        await prefs.setString(_lastViewedWeekKey(userId), saveWeek);
        await prefs.setString(_lastViewedTermKey(userId), saveTerm);
      }
      if (updateWidgetPins) {
        await prefs.setString(_widgetWeekKey(userId), saveWeek);
        await prefs.setString(_widgetTermKey(userId), saveTerm);
      }
      final newWidgetWeek = _effectiveWidgetWeek(prefs, userId);
      final newWidgetTerm = _effectiveWidgetTerm(prefs, userId);
      if (oldWidgetWeek != newWidgetWeek || oldWidgetTerm != newWidgetTerm) {
        await _removeStaleWidgetProjections(
          prefs: prefs,
          userId: userId,
          oldYearTerm: oldWidgetTerm,
          oldWeekNum: oldWidgetWeek,
          newYearTerm: newWidgetTerm,
          newWeekNum: newWidgetWeek,
        );
      }
      final updatesVisibleWidgetProjection =
          await _writeWidgetProjectionIfPinned(
            prefs: prefs,
            userId: userId,
            yearTerm: saveTerm,
            weekNum: saveWeek,
            schedule: merged,
          );
      await ScheduleRefreshState.markSuccess(userId, refreshId: refreshId);
      await prefs.setInt(
        lastFetchAtKey(userId, saveTerm, saveWeek),
        fetchedAt.millisecondsSinceEpoch,
      );
      if (updatesVisibleWidgetProjection) {
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
    final uniqueWeeks = weeks.toSet();
    await ScheduleCacheDatabase.instance.deleteWeeks(
      userId: userId,
      yearTerm: yearTerm,
      weekNums: uniqueWeeks.map((week) => week.toString()),
    );
    for (final week in uniqueWeeks) {
      final weekNum = week.toString();
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
    final entry = await ScheduleCacheDatabase.instance.load(
      userId: userId,
      yearTerm: _norm(yearTerm),
      weekNum: _norm(weekNum),
    );
    return entry?.rawJson;
  }

  Future<void> saveScheduleJson({
    required String userId,
    required String yearTerm,
    required String weekNum,
    required String jsonStr,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedTerm = _norm(yearTerm);
    final normalizedWeek = _norm(weekNum);
    final fetchedAt = DateTime.now();
    await ScheduleCacheDatabase.instance.upsert(
      userId: userId,
      yearTerm: normalizedTerm,
      weekNum: normalizedWeek,
      rawJson: jsonStr,
      fetchedAt: fetchedAt,
    );
    final stored = await ScheduleCacheDatabase.instance.load(
      userId: userId,
      yearTerm: normalizedTerm,
      weekNum: normalizedWeek,
    );
    final decoded = json.decode(stored?.rawJson ?? jsonStr);
    var updatesVisibleWidgetProjection = false;
    if (decoded is Map<String, dynamic>) {
      final merged = await ScheduleCustomizationManager.instance
          .applyToSchedule(
            userId: userId,
            schedule: ScheduleData.fromJson(decoded),
          );
      updatesVisibleWidgetProjection = await _writeWidgetProjectionIfPinned(
        prefs: prefs,
        userId: userId,
        yearTerm: normalizedTerm,
        weekNum: normalizedWeek,
        schedule: merged,
      );
    }
    await ScheduleRefreshState.markSuccess(userId);
    await prefs.setInt(
      lastFetchAtKey(userId, normalizedTerm, normalizedWeek),
      fetchedAt.millisecondsSinceEpoch,
    );
    if (updatesVisibleWidgetProjection) {
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

  String? _effectiveWidgetWeek(SharedPreferences prefs, String userId) =>
      prefs.getString(_widgetWeekKey(userId))?.trim() ??
      prefs.getString(_lastViewedWeekKey(userId))?.trim();

  String? _effectiveWidgetTerm(SharedPreferences prefs, String userId) =>
      prefs.getString(_widgetTermKey(userId))?.trim() ??
      prefs.getString(_lastViewedTermKey(userId))?.trim();

  Future<bool> _writeWidgetProjectionIfPinned({
    required SharedPreferences prefs,
    required String userId,
    required String yearTerm,
    required String weekNum,
    required ScheduleData schedule,
  }) async {
    final pinnedWeek = _effectiveWidgetWeek(prefs, userId);
    final pinnedTerm = _effectiveWidgetTerm(prefs, userId);
    if (!isWidgetProjectionVisible(
      yearTerm: yearTerm,
      weekNum: weekNum,
      pinnedYearTerm: pinnedTerm,
      pinnedWeekNum: pinnedWeek,
    )) {
      return false;
    }
    await prefs.setString(
      _scheduleKey(userId, yearTerm, weekNum),
      json.encode(schedule.toJson()),
    );
    return true;
  }

  Future<void> _removeStaleWidgetProjections({
    required SharedPreferences prefs,
    required String userId,
    required String? oldYearTerm,
    required String? oldWeekNum,
    required String? newYearTerm,
    required String? newWeekNum,
  }) async {
    final oldWeeks = _projectionWeeks(oldWeekNum);
    if (oldYearTerm == null || oldWeeks.isEmpty) return;
    final newKeys = <String>{
      if (newYearTerm != null)
        for (final week in _projectionWeeks(newWeekNum))
          _scheduleKey(userId, newYearTerm, week),
    };
    for (final week in oldWeeks) {
      final key = _scheduleKey(userId, oldYearTerm, week);
      if (!newKeys.contains(key)) await prefs.remove(key);
    }
  }

  static bool isWidgetProjectionVisible({
    required String yearTerm,
    required String weekNum,
    required String? pinnedYearTerm,
    required String? pinnedWeekNum,
  }) {
    if (pinnedYearTerm != yearTerm || pinnedWeekNum == null) return false;
    return _projectionWeeks(pinnedWeekNum).contains(weekNum);
  }

  static Set<String> _projectionWeeks(String? centerWeek) {
    final parsed = int.tryParse(centerWeek ?? '');
    if (parsed == null) {
      return centerWeek == null || centerWeek.isEmpty
          ? const <String>{}
          : <String>{centerWeek};
    }
    return <String>{
      if (parsed > 1) (parsed - 1).toString(),
      parsed.toString(),
      (parsed + 1).toString(),
    };
  }
}
