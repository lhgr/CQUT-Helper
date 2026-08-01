import 'dart:convert';
import 'dart:math';

import 'package:cqut_helper/manager/course_color_assignment_manager.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/local_schedule_model.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

class ScheduleCustomizationManager extends ChangeNotifier {
  ScheduleCustomizationManager._();

  static final ScheduleCustomizationManager instance =
      ScheduleCustomizationManager._();

  static const int databaseVersion = 1;
  static const String _databaseName = 'schedule_customizations.db';
  static const String _rawSchedulePrefix = 'schedule_remote_';

  Database? _database;
  final Random _random = Random.secure();

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), _databaseName);
    final opened = await openDatabase(
      path,
      version: databaseVersion,
      onCreate: (db, version) async {
        await db.execute('''
CREATE TABLE local_events (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  year_term TEXT NOT NULL,
  title TEXT NOT NULL,
  teacher TEXT NOT NULL DEFAULT '',
  location TEXT NOT NULL DEFAULT '',
  note TEXT NOT NULL DEFAULT '',
  weeks_json TEXT NOT NULL DEFAULT '[]',
  week_day INTEGER NOT NULL,
  start_session INTEGER NOT NULL,
  session_count INTEGER NOT NULL,
  specific_date TEXT,
  reminder_minutes INTEGER,
  color_index INTEGER,
  source TEXT NOT NULL DEFAULT 'manual',
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
)
''');
        await db.execute(
          'CREATE INDEX local_events_scope_idx '
          'ON local_events(user_id, year_term)',
        );
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
    );
    _database = opened;
    return opened;
  }

  String newId() {
    final now = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = List.generate(
      8,
      (_) => _random.nextInt(36).toRadixString(36),
    ).join();
    return '$now$suffix';
  }

  Future<List<LocalScheduleEvent>> listLocalEvents({
    required String userId,
    required String yearTerm,
  }) async {
    final rows = await (await _db).query(
      'local_events',
      where: 'user_id = ? AND year_term = ?',
      whereArgs: [userId, yearTerm],
      orderBy: 'specific_date, week_day, start_session, title',
    );
    return rows.map(LocalScheduleEvent.fromDatabaseMap).toList();
  }

  Future<void> saveLocalEvent(LocalScheduleEvent event) async {
    await (await _db).insert(
      'local_events',
      event.toDatabaseMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (event.colorIndex != null) {
      await CourseColorAssignmentManager.instance.setAssignment(
        term: event.yearTerm,
        courseKey: event.title,
        colorIndex: event.colorIndex!,
      );
    }
    await _afterMutation(event.userId);
  }

  Future<void> saveLocalEvents(Iterable<LocalScheduleEvent> events) async {
    final items = events.toList(growable: false);
    if (items.isEmpty) return;
    final db = await _db;
    await db.transaction((txn) async {
      for (final event in items) {
        await txn.insert(
          'local_events',
          event.toDatabaseMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    for (final event in items) {
      if (event.colorIndex != null) {
        await CourseColorAssignmentManager.instance.setAssignment(
          term: event.yearTerm,
          courseKey: event.title,
          colorIndex: event.colorIndex!,
        );
      }
    }
    await _afterMutation(items.first.userId);
  }

  Future<void> deleteLocalEvent(LocalScheduleEvent event) async {
    await (await _db).delete(
      'local_events',
      where: 'id = ? AND user_id = ?',
      whereArgs: [event.id, event.userId],
    );
    await _afterMutation(event.userId);
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
    final week = int.tryParse((schedule.weekNum ?? '').trim());
    if (userId.trim().isEmpty || term.isEmpty || week == null) {
      return schedule;
    }
    final preferences = await preferenceMap(userId: userId, yearTerm: term);
    final localEvents = await listLocalEvents(userId: userId, yearTerm: term);
    final weekDates = scheduleDates(schedule);
    final merged = <EventItem>[];

    for (final event in schedule.eventList ?? const <EventItem>[]) {
      if (event.isLocal == true) continue;
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

    for (final local in localEvents) {
      if (!local.appliesToWeek(week, weekDates.values)) continue;
      var weekday = local.weekDay;
      if (local.specificDate != null) {
        for (final entry in weekDates.entries) {
          if (localScheduleSameDate(entry.value, local.specificDate!)) {
            weekday = entry.key;
            break;
          }
        }
      }
      merged.add(
        EventItem(
          weekNum: week.toString(),
          weekDay: weekday.toString(),
          weekList: [week.toString()],
          weekCover: local.specificDate == null
              ? '第$week周'
              : localScheduleDateKey(local.specificDate!),
          sessionList: List.generate(
            local.sessionCount,
            (index) => (local.startSession + index).toString(),
          ),
          sessionStart: local.startSession.toString(),
          sessionLast: local.sessionCount.toString(),
          eventName: local.title,
          address: local.location,
          memberName: local.teacher,
          eventType: local.source == LocalScheduleSource.ics
              ? 'local_ics'
              : 'local_manual',
          eventID: 'local:${local.id}',
          localId: local.id,
          note: local.note,
          isLocal: true,
          specificDate: local.specificDate == null
              ? null
              : localScheduleDateKey(local.specificDate!),
          reminderMinutes: local.reminderMinutes,
          colorIndex: local.colorIndex,
          customizationKey: local.title,
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
        'local_events',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
      await txn.delete(
        'course_preferences',
        where: 'user_id = ?',
        whereArgs: [userId],
      );
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
    for (final item in schedule.weekDayList ?? const <WeekDayItem>[]) {
      final weekday = int.tryParse((item.weekDay ?? '').trim());
      final date = parseScheduleDate(item.weekDate);
      if (weekday != null && date != null) result[weekday] = date;
    }
    return result;
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
