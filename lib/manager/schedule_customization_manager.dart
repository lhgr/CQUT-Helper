import 'dart:convert';

import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/course_preference_model.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class ScheduleCustomizationManager extends ChangeNotifier {
  ScheduleCustomizationManager._();

  static final ScheduleCustomizationManager instance =
      ScheduleCustomizationManager._();

  static const int databaseVersion = 2;
  static const String _databaseName = 'schedule_customizations.db';
  static const String _rawSchedulePrefix = 'schedule_remote_';

  Database? _database;
  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), _databaseName);
    final opened = await openDatabase(
      path,
      version: databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE course_preferences (
  user_id TEXT NOT NULL,
  year_term TEXT NOT NULL,
  course_key TEXT NOT NULL,
  display_name TEXT,
  teacher TEXT,
  location TEXT,
  note TEXT NOT NULL DEFAULT '',
  hidden INTEGER NOT NULL DEFAULT 0,
  reminder_minutes INTEGER,
  color_index INTEGER,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY(user_id, year_term, course_key)
)
''');
      },
      // Version 1 may contain the retired local_events table. Leave it intact
      // so upgrading does not destroy a user's existing local data.
      onUpgrade: (db, oldVersion, newVersion) async {},
    );
    _database = opened;
    return opened;
  }

  Future<Map<String, CoursePreference>> preferenceMap({
    required String userId,
    required String yearTerm,
  }) async {
    final rows = await (await _db).query(
      'course_preferences',
      where: 'user_id = ? AND year_term = ?',
      whereArgs: [userId, yearTerm],
    );
    final result = <String, CoursePreference>{};
    for (final row in rows) {
      final preference = CoursePreference.fromDatabaseMap(row);
      result[preference.courseKey] = preference;
    }
    return result;
  }

  Future<CoursePreference?> preferenceFor({
    required String userId,
    required String yearTerm,
    required String courseKey,
  }) async {
    final rows = await (await _db).query(
      'course_preferences',
      where: 'user_id = ? AND year_term = ? AND course_key = ?',
      whereArgs: [userId, yearTerm, courseKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return CoursePreference.fromDatabaseMap(rows.first);
  }

  Future<List<HiddenCourseInfo>> hiddenCourses({
    required String userId,
    required String yearTerm,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedTerm = yearTerm.trim();
    if (normalizedUserId.isEmpty || normalizedTerm.isEmpty) return const [];

    final preferences = await preferenceMap(
      userId: normalizedUserId,
      yearTerm: normalizedTerm,
    );
    final hiddenPreferences = preferences.values
        .where((preference) => preference.hidden)
        .toList(growable: false);
    if (hiddenPreferences.isEmpty) return const [];

    final cachedEvents = <String, EventItem>{};
    final prefs = await SharedPreferences.getInstance();
    final rawPrefix =
        '$_rawSchedulePrefix${normalizedUserId}_${normalizedTerm}_';
    for (final key in prefs.getKeys().where(
      (key) => key.startsWith(rawPrefix),
    )) {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final schedule = ScheduleData.fromJson(decoded.cast<String, dynamic>());
        for (final event in schedule.eventList ?? const <EventItem>[]) {
          cachedEvents.putIfAbsent(courseKeyForEvent(event), () => event);
        }
      } catch (_) {}
    }

    final result = hiddenPreferences
        .map(
          (preference) => HiddenCourseInfo(
            preference: preference,
            cachedEvent: cachedEvents[preference.courseKey],
          ),
        )
        .toList(growable: false);
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  Future<void> saveCoursePreference(CoursePreference preference) async {
    await (await _db).insert(
      'course_preferences',
      preference.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (preference.colorIndex != null) {
      await CourseColorAssignmentManager.instance.setAssignment(
        term: preference.yearTerm,
        courseKey: preference.displayName ?? preference.courseKey,
        colorIndex: preference.colorIndex!,
      );
    }
    await _afterMutation(preference.userId);
  }

  Future<void> deleteCoursePreference(CoursePreference preference) async {
    await (await _db).delete(
      'course_preferences',
      where: 'user_id = ? AND year_term = ? AND course_key = ?',
      whereArgs: [preference.userId, preference.yearTerm, preference.courseKey],
    );
    await _afterMutation(preference.userId);
  }

  Future<ScheduleData> applyToSchedule({
    required String userId,
    required ScheduleData schedule,
  }) async {
    final term = (schedule.yearTerm ?? '').trim();
    if (userId.trim().isEmpty || term.isEmpty) {
      return schedule;
    }
    final preferences = await preferenceMap(userId: userId, yearTerm: term);
    final merged = <EventItem>[];

    for (final event in schedule.eventList ?? const <EventItem>[]) {
      final eventType = (event.eventType ?? '').trim();
      final eventId = (event.eventID ?? '').trim();
      if (eventType.startsWith('local_') || eventId.startsWith('local:')) {
        continue;
      }
      final key = courseKeyForEvent(event);
      final preference = preferences[key];
      if (preference?.hidden == true) continue;
      merged.add(
        event.copyWith(
          eventName: preference?.displayName,
          memberName: preference?.teacher,
          address: preference?.location,
          note: preference?.note,
          reminderMinutes: preference?.reminderMinutes,
          colorIndex: preference?.colorIndex,
          customizationKey: key,
        ),
      );
    }
    merged.sort(_compareEvents);
    return schedule.copyWith(eventList: merged);
  }

  Future<void> rebuildDisplayCaches(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith('$_rawSchedulePrefix${userId}_'))
        .toList(growable: false);
    for (final key in keys) {
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final source = ScheduleData.fromJson(decoded.cast<String, dynamic>());
        final merged = await applyToSchedule(userId: userId, schedule: source);
        final displayKey = key.replaceFirst(_rawSchedulePrefix, 'schedule_');
        await prefs.setString(displayKey, jsonEncode(merged.toJson()));
      } catch (_) {}
    }
    await WidgetUpdater.updateTodayWidget(trigger: 'custom_schedule_changed');
  }

  Future<void> clearUserData(String userId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'course_preferences',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      final legacyTable = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
        const ['local_events'],
      );
      if (legacyTable.isNotEmpty) {
        await txn.delete(
          'local_events',
          where: 'user_id = ?',
          whereArgs: [userId],
        );
      }
    });
    notifyListeners();
  }

  Future<void> _afterMutation(String userId) async {
    await rebuildDisplayCaches(userId);
    await CourseReminderScheduler.rescheduleForUser(userId);
    notifyListeners();
  }

  static String courseKeyForEvent(EventItem event) {
    final name = (event.eventName ?? '').trim();
    final teacher = (event.memberName ?? '').trim();
    return 'course:$name|$teacher';
  }

  static Map<int, DateTime> scheduleDates(ScheduleData schedule) {
    final result = <int, DateTime>{};
    final days = schedule.weekDayList ?? const <WeekDayItem>[];
    for (var index = 0; index < days.length; index++) {
      final item = days[index];
      final weekday = _parseWeekday(item.weekDay) ?? index + 1;
      final date = parseScheduleDate(item.weekDate);
      if (weekday >= 1 && weekday <= 7 && date != null) {
        result[weekday] = date;
      }
    }
    return result;
  }

  static int? _parseWeekday(String? raw) {
    final value = (raw ?? '').trim();
    final numeric = int.tryParse(value);
    if (numeric != null) return numeric;

    const chineseWeekdays = <String, int>{
      '一': 1,
      '二': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '日': 7,
      '天': 7,
    };
    for (final entry in chineseWeekdays.entries) {
      if (value.endsWith(entry.key)) return entry.value;
    }
    return null;
  }

  static DateTime? parseScheduleDate(String? raw, {DateTime? around}) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final numbers = RegExp(
      r'\d+',
    ).allMatches(value).map((m) => m.group(0)!).toList();
    if (numbers.length < 2) return null;
    if (numbers.first.length == 4 && numbers.length >= 3) {
      final year = int.tryParse(numbers[0]);
      final month = int.tryParse(numbers[1]);
      final day = int.tryParse(numbers[2]);
      if (year == null || month == null || day == null) return null;
      return _safeDate(year, month, day);
    }
    final month = int.tryParse(numbers[0]);
    final day = int.tryParse(numbers[1]);
    if (month == null || day == null) return null;
    final anchor = around ?? DateTime.now();
    final candidates = [
      _safeDate(anchor.year - 1, month, day),
      _safeDate(anchor.year, month, day),
      _safeDate(anchor.year + 1, month, day),
    ].whereType<DateTime>().toList();
    candidates.sort(
      (a, b) =>
          a.difference(anchor).abs().compareTo(b.difference(anchor).abs()),
    );
    return candidates.isEmpty ? null : candidates.first;
  }

  static DateTime? _safeDate(int year, int month, int day) {
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final result = DateTime(year, month, day);
    if (result.year != year || result.month != month || result.day != day) {
      return null;
    }
    return result;
  }

  static int _compareEvents(EventItem a, EventItem b) {
    final day = (int.tryParse(a.weekDay ?? '') ?? 9).compareTo(
      int.tryParse(b.weekDay ?? '') ?? 9,
    );
    if (day != 0) return day;
    final start = (int.tryParse(a.sessionStart ?? '') ?? 99).compareTo(
      int.tryParse(b.sessionStart ?? '') ?? 99,
    );
    if (start != 0) return start;
    return (a.eventName ?? '').compareTo(b.eventName ?? '');
  }
}

class HiddenCourseInfo {
  final CoursePreference preference;
  final EventItem? cachedEvent;

  const HiddenCourseInfo({required this.preference, required this.cachedEvent});

  String get displayName {
    final preferred = (preference.displayName ?? '').trim();
    if (preferred.isNotEmpty) return preferred;
    final cached = (cachedEvent?.eventName ?? '').trim();
    if (cached.isNotEmpty) return cached;
    return _courseKeyParts.$1.isEmpty ? '未命名课程' : _courseKeyParts.$1;
  }

  String get teacher {
    final preferred = (preference.teacher ?? '').trim();
    if (preferred.isNotEmpty) return preferred;
    final cached = (cachedEvent?.memberName ?? '').trim();
    if (cached.isNotEmpty) return cached;
    return _courseKeyParts.$2;
  }

  String get location {
    final preferred = (preference.location ?? '').trim();
    if (preferred.isNotEmpty) return preferred;
    return (cachedEvent?.address ?? '').trim();
  }

  (String, String) get _courseKeyParts {
    final value = preference.courseKey.startsWith('course:')
        ? preference.courseKey.substring('course:'.length)
        : preference.courseKey;
    final separator = value.lastIndexOf('|');
    if (separator < 0) return (value.trim(), '');
    return (
      value.substring(0, separator).trim(),
      value.substring(separator + 1).trim(),
    );
  }
}
