import 'dart:convert';

import 'package:cqut_helper/utils/app_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

@immutable
class ScheduleCacheEntry {
  const ScheduleCacheEntry({
    required this.userId,
    required this.yearTerm,
    required this.weekNum,
    required this.rawJson,
    required this.fetchedAt,
  });

  final String userId;
  final String yearTerm;
  final String weekNum;
  final String rawJson;
  final DateTime fetchedAt;
}

@immutable
class ScheduleLegacyCacheRecord {
  const ScheduleLegacyCacheRecord({
    required this.userId,
    required this.yearTerm,
    required this.weekNum,
    required this.rawJson,
    required this.isRemoteSource,
  });

  final String userId;
  final String yearTerm;
  final String weekNum;
  final String rawJson;
  final bool isRemoteSource;

  String get identity => '$userId\u0000$yearTerm\u0000$weekNum';
}

/// Versioned source-of-truth cache for week schedules.
///
/// SharedPreferences retains only small state values and a three-week
/// projection window consumed by the native Android widget.
class ScheduleCacheDatabase {
  ScheduleCacheDatabase._();

  static final ScheduleCacheDatabase instance = ScheduleCacheDatabase._();

  static const int databaseVersion = 2;
  static const int dataVersion = 1;
  static const String databaseName = 'schedule_cache.db';
  static const String _migrationKey = 'legacy_shared_preferences_v1';

  Database? _database;
  Future<Database>? _opening;

  Future<Database> get _db {
    final existing = _database;
    if (existing != null) return Future.value(existing);
    final opening = _opening;
    if (opening != null) return opening;
    final future = _openAndMigrate();
    _opening = future;
    future.then(
      (_) {
        if (identical(_opening, future)) _opening = null;
      },
      onError: (Object _, StackTrace _) {
        if (identical(_opening, future)) _opening = null;
      },
    );
    return future;
  }

  Future<Database> _openAndMigrate() async {
    final path = p.join(await getDatabasesPath(), databaseName);
    Database? opened;
    try {
      opened = await _open(path);
      await _migrateLegacyPreferences(opened);
      _database = opened;
      return opened;
    } catch (error, stackTrace) {
      if (!_isCorruption(error)) {
        await opened?.close();
        rethrow;
      }
      AppLogger.I.warn(
        'ScheduleCache',
        'schedule cache database is corrupt; recreating it',
        error: error,
        stackTrace: stackTrace,
        fields: const {'event': 'schedule_cache_database_recovery'},
      );
      await opened?.close();
      await _database?.close();
      _database = null;
      await deleteDatabase(path);
      final db = await _open(path);
      await _migrateLegacyPreferences(db);
      _database = db;
      return db;
    }
  }

  Future<Database> _open(String path) {
    return openDatabase(
      path,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async {
        await _createVersion1(db);
        if (version >= 2) await _upgradeToVersion2(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 1) await _createVersion1(db);
        if (oldVersion < 2 && newVersion >= 2) {
          await _upgradeToVersion2(db);
        }
      },
    );
  }

  static Future<void> _createVersion1(DatabaseExecutor db) async {
    await db.execute('''
CREATE TABLE schedule_weeks (
  user_id TEXT NOT NULL,
  year_term TEXT NOT NULL,
  week_num TEXT NOT NULL,
  raw_json TEXT NOT NULL,
  checksum TEXT NOT NULL,
  fetched_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  data_version INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY(user_id, year_term, week_num)
)
''');
    await db.execute('''
CREATE TABLE cache_meta (
  key TEXT NOT NULL PRIMARY KEY,
  value TEXT NOT NULL
)
''');
  }

  static Future<void> _upgradeToVersion2(DatabaseExecutor db) async {
    await db.execute(
      'ALTER TABLE schedule_weeks ADD COLUMN last_verified_at INTEGER',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS schedule_weeks_fetched_at_idx '
      'ON schedule_weeks(fetched_at)',
    );
  }

  Future<void> upsert({
    required String userId,
    required String yearTerm,
    required String weekNum,
    required String rawJson,
    DateTime? fetchedAt,
  }) async {
    final normalizedUser = userId.trim();
    final normalizedTerm = yearTerm.trim();
    final normalizedWeek = weekNum.trim();
    if (normalizedUser.isEmpty ||
        normalizedTerm.isEmpty ||
        normalizedWeek.isEmpty) {
      throw const FormatException('课表缓存缺少用户、学期或周次');
    }
    final canonical = canonicalizeAndValidate(
      rawJson,
      expectedYearTerm: normalizedTerm,
      expectedWeekNum: normalizedWeek,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    final values = <String, Object?>{
      'user_id': normalizedUser,
      'year_term': normalizedTerm,
      'week_num': normalizedWeek,
      'raw_json': canonical,
      'checksum': checksumFor(canonical),
      'fetched_at': (fetchedAt ?? DateTime.now()).millisecondsSinceEpoch,
      'updated_at': now,
      'last_verified_at': now,
      'data_version': dataVersion,
    };
    try {
      await (await _db).insert(
        'schedule_weeks',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (error, stackTrace) {
      if (!await _recoverCorruptDatabase(error, stackTrace)) rethrow;
      await (await _db).insert(
        'schedule_weeks',
        values,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<ScheduleCacheEntry?> load({
    required String userId,
    required String yearTerm,
    required String weekNum,
  }) async {
    final user = userId.trim();
    final term = yearTerm.trim();
    final week = weekNum.trim();
    try {
      final rows = await (await _db).query(
        'schedule_weeks',
        where: 'user_id = ? AND year_term = ? AND week_num = ?',
        whereArgs: [user, term, week],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return await _verifiedEntry(rows.first);
    } catch (error, stackTrace) {
      if (await _recoverCorruptDatabase(error, stackTrace)) return null;
      rethrow;
    }
  }

  Future<List<ScheduleCacheEntry>> loadAllForUser(
    String userId, {
    String? yearTerm,
  }) async {
    final user = userId.trim();
    if (user.isEmpty) return const [];
    try {
      final term = yearTerm?.trim();
      final rows = await (await _db).query(
        'schedule_weeks',
        where: term == null || term.isEmpty
            ? 'user_id = ?'
            : 'user_id = ? AND year_term = ?',
        whereArgs: term == null || term.isEmpty ? [user] : [user, term],
        orderBy: 'year_term, CAST(week_num AS INTEGER), week_num',
      );
      final entries = <ScheduleCacheEntry>[];
      for (final row in rows) {
        final entry = await _verifiedEntry(row);
        if (entry != null) entries.add(entry);
      }
      return entries;
    } catch (error, stackTrace) {
      if (await _recoverCorruptDatabase(error, stackTrace)) return const [];
      rethrow;
    }
  }

  Future<ScheduleCacheEntry?> _verifiedEntry(Map<String, Object?> row) async {
    final user = (row['user_id'] ?? '').toString();
    final term = (row['year_term'] ?? '').toString();
    final week = (row['week_num'] ?? '').toString();
    final raw = (row['raw_json'] ?? '').toString();
    final storedChecksum = (row['checksum'] ?? '').toString();
    String? reason;
    if ((row['data_version'] as num?)?.toInt() != dataVersion) {
      reason = 'unsupported_data_version';
    } else if (!checksumMatches(raw, storedChecksum)) {
      reason = 'checksum_mismatch';
    } else {
      try {
        canonicalizeAndValidate(
          raw,
          expectedYearTerm: term,
          expectedWeekNum: week,
        );
      } catch (_) {
        reason = 'invalid_json_structure';
      }
    }
    if (reason != null) {
      await (await _db).delete(
        'schedule_weeks',
        where: 'user_id = ? AND year_term = ? AND week_num = ?',
        whereArgs: [user, term, week],
      );
      AppLogger.I.warn(
        'ScheduleCache',
        'discarded invalid week cache',
        fields: {
          'event': 'schedule_cache_row_recovery',
          'reason': reason,
          'year_term': term,
          'week_num': week,
        },
      );
      return null;
    }
    final verifiedAt = DateTime.now().millisecondsSinceEpoch;
    final previousVerifiedAt = (row['last_verified_at'] as num?)?.toInt() ?? 0;
    if (verifiedAt - previousVerifiedAt >
        const Duration(days: 1).inMilliseconds) {
      await (await _db).update(
        'schedule_weeks',
        {'last_verified_at': verifiedAt},
        where: 'user_id = ? AND year_term = ? AND week_num = ?',
        whereArgs: [user, term, week],
      );
    }
    return ScheduleCacheEntry(
      userId: user,
      yearTerm: term,
      weekNum: week,
      rawJson: raw,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['fetched_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  Future<DateTime?> fetchedAt({
    required String userId,
    required String yearTerm,
    required String weekNum,
  }) async {
    final entry = await load(
      userId: userId,
      yearTerm: yearTerm,
      weekNum: weekNum,
    );
    return entry?.fetchedAt;
  }

  Future<int> countForUser(String userId) async {
    final rows = await (await _db).rawQuery(
      'SELECT COUNT(*) AS count FROM schedule_weeks WHERE user_id = ?',
      [userId.trim()],
    );
    return rows.isEmpty ? 0 : (rows.first['count'] as num?)?.toInt() ?? 0;
  }

  Future<int> estimatedBytes() async {
    final rows = await (await _db).rawQuery(
      'SELECT COALESCE(SUM(LENGTH(raw_json) + LENGTH(checksum) + '
      'LENGTH(user_id) + LENGTH(year_term) + LENGTH(week_num)), 0) AS bytes '
      'FROM schedule_weeks',
    );
    return rows.isEmpty ? 0 : (rows.first['bytes'] as num?)?.toInt() ?? 0;
  }

  Future<int> deleteWeeks({
    required String userId,
    required String yearTerm,
    required Iterable<String> weekNums,
  }) async {
    final weeks = weekNums.map((value) => value.trim()).toSet()..remove('');
    if (weeks.isEmpty) return 0;
    final placeholders = List.filled(weeks.length, '?').join(',');
    return (await _db).delete(
      'schedule_weeks',
      where: 'user_id = ? AND year_term = ? AND week_num IN ($placeholders)',
      whereArgs: [userId.trim(), yearTerm.trim(), ...weeks],
    );
  }

  Future<int> clearUser(String userId) async {
    return (await _db).delete(
      'schedule_weeks',
      where: 'user_id = ?',
      whereArgs: [userId.trim()],
    );
  }

  Future<int> clearAll() => _db.then((db) => db.delete('schedule_weeks'));

  Future<void> _migrateLegacyPreferences(Database db) async {
    final migrated = await db.query(
      'cache_meta',
      columns: const ['value'],
      where: 'key = ?',
      whereArgs: const [_migrationKey],
      limit: 1,
    );
    final prefs = await SharedPreferences.getInstance();
    if (migrated.isNotEmpty) {
      await _cleanupLegacyPreferences(prefs);
      return;
    }

    final records = <String, ScheduleLegacyCacheRecord>{};
    final keys = prefs.getKeys().toList(growable: false)..sort();
    // Display projections are a fallback only; raw remote responses win.
    for (final remote in const [false, true]) {
      for (final key in keys) {
        final rawValue = prefs.get(key);
        if (rawValue is! String) continue;
        final record = parseLegacyRecord(key, rawValue);
        if (record == null || record.isRemoteSource != remote) continue;
        records[record.identity] = record;
      }
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final record in records.values) {
        final fetchKey =
            'schedule_fetch_at_${record.userId}_${record.yearTerm}_${record.weekNum}';
        final fetchedAt = prefs.getInt(fetchKey) ?? now;
        await txn.insert('schedule_weeks', {
          'user_id': record.userId,
          'year_term': record.yearTerm,
          'week_num': record.weekNum,
          'raw_json': record.rawJson,
          'checksum': checksumFor(record.rawJson),
          'fetched_at': fetchedAt,
          'updated_at': now,
          'last_verified_at': now,
          'data_version': dataVersion,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await txn.insert('cache_meta', {
        'key': _migrationKey,
        'value': now.toString(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });

    await _cleanupLegacyPreferences(prefs);
    if (records.isNotEmpty) {
      AppLogger.I.info(
        'ScheduleCache',
        'migrated legacy week schedules to SQLite',
        fields: {
          'event': 'schedule_cache_legacy_migration',
          'weeks': records.length,
        },
      );
    }
  }

  Future<void> _cleanupLegacyPreferences(SharedPreferences prefs) async {
    final keys = prefs.getKeys().toList(growable: false);
    for (final key in keys) {
      final isRemote = key.startsWith('schedule_remote_');
      final looksLikeDisplayWeek = RegExp(
        r'^schedule_.+_\d{4}-\d{4}-\d+_\d+$',
      ).hasMatch(key);
      if (!isRemote && !looksLikeDisplayWeek) continue;
      final raw = prefs.get(key);
      final record = raw is String ? parseLegacyRecord(key, raw) : null;
      if (isRemote || record == null || !_isPinnedProjection(prefs, record)) {
        await prefs.remove(key);
      }
    }
  }

  static bool _isPinnedProjection(
    SharedPreferences prefs,
    ScheduleLegacyCacheRecord record,
  ) {
    final widgetTerm =
        prefs.getString('schedule_widget_term_${record.userId}')?.trim() ??
        prefs.getString('schedule_last_term_${record.userId}')?.trim();
    final widgetWeek =
        prefs.getString('schedule_widget_week_${record.userId}')?.trim() ??
        prefs.getString('schedule_last_week_${record.userId}')?.trim();
    if (widgetTerm != record.yearTerm || widgetWeek == null) return false;
    final pinned = int.tryParse(widgetWeek);
    final candidate = int.tryParse(record.weekNum);
    if (pinned == null || candidate == null) {
      return widgetWeek == record.weekNum;
    }
    return (pinned - candidate).abs() <= 1;
  }

  @visibleForTesting
  static ScheduleLegacyCacheRecord? parseLegacyRecord(
    String key,
    String rawJson,
  ) {
    const remotePrefix = 'schedule_remote_';
    const displayPrefix = 'schedule_';
    final isRemote = key.startsWith(remotePrefix);
    if (!isRemote && !key.startsWith(displayPrefix)) return null;
    if (!isRemote &&
        (key.startsWith('schedule_fetch_at_') ||
            key.startsWith('schedule_fp_') ||
            key.startsWith('schedule_widget_') ||
            key.startsWith('schedule_last_'))) {
      return null;
    }
    final prefix = isRemote ? remotePrefix : displayPrefix;
    try {
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map) return null;
      final map = decoded.cast<String, dynamic>();
      var term = (map['yearTerm'] ?? '').toString().trim();
      var week = (map['weekNum'] ?? '').toString().trim();
      final body = key.substring(prefix.length);
      if (term.isEmpty || week.isEmpty) {
        final inferred = RegExp(
          r'^(.*)_(\d{4}-\d{4}-\d+)_(\d+)$',
        ).firstMatch(body);
        if (inferred == null) return null;
        term = inferred.group(2)!;
        week = inferred.group(3)!;
      }
      if (term.isEmpty || week.isEmpty) return null;
      final suffix = '_${term}_$week';
      if (!body.endsWith(suffix)) return null;
      final user = body.substring(0, body.length - suffix.length).trim();
      if (user.isEmpty) return null;
      final canonical = canonicalizeAndValidate(
        rawJson,
        expectedYearTerm: term,
        expectedWeekNum: week,
      );
      return ScheduleLegacyCacheRecord(
        userId: user,
        yearTerm: term,
        weekNum: week,
        rawJson: canonical,
        isRemoteSource: isRemote,
      );
    } catch (_) {
      return null;
    }
  }

  @visibleForTesting
  static String canonicalizeAndValidate(
    String rawJson, {
    required String expectedYearTerm,
    required String expectedWeekNum,
  }) {
    final decoded = jsonDecode(rawJson);
    if (decoded is! Map) {
      throw const FormatException('课表缓存根节点不是对象');
    }
    final map = decoded.cast<String, dynamic>();
    if (map.containsKey('eventList') && map['eventList'] is! List) {
      throw const FormatException('课表缓存 eventList 类型错误');
    }
    if (map.containsKey('weekDayList') && map['weekDayList'] is! List) {
      throw const FormatException('课表缓存 weekDayList 类型错误');
    }
    if (map['eventList'] is! List && map['weekDayList'] is! List) {
      throw const FormatException('课表缓存缺少课程与日期列表');
    }
    for (final field in const ['yearTermList', 'weekList']) {
      if (map.containsKey(field) && map[field] is! List) {
        throw FormatException('课表缓存 $field 类型错误');
      }
    }
    for (final event in (map['eventList'] as List?) ?? const <Object?>[]) {
      if (event is! Map) {
        throw const FormatException('课表缓存包含无效课程');
      }
      for (final field in const ['weekList', 'sessionList']) {
        if (event.containsKey(field) && event[field] is! List) {
          throw FormatException('课表缓存课程 $field 类型错误');
        }
      }
    }
    for (final day in (map['weekDayList'] as List?) ?? const <Object?>[]) {
      if (day is! Map) {
        throw const FormatException('课表缓存包含无效日期');
      }
    }
    final actualTerm = (map['yearTerm'] ?? '').toString().trim();
    final actualWeek = (map['weekNum'] ?? '').toString().trim();
    if (actualTerm.isNotEmpty && actualTerm != expectedYearTerm) {
      throw const FormatException('课表缓存学期不匹配');
    }
    if (actualWeek.isNotEmpty && actualWeek != expectedWeekNum) {
      throw const FormatException('课表缓存周次不匹配');
    }
    map['yearTerm'] = expectedYearTerm;
    map['weekNum'] = expectedWeekNum;
    map.putIfAbsent('eventList', () => <Object?>[]);
    return jsonEncode(map);
  }

  @visibleForTesting
  static String checksumFor(String rawJson) =>
      sha256.convert(utf8.encode(rawJson)).toString();

  @visibleForTesting
  static bool checksumMatches(String rawJson, String expectedChecksum) =>
      expectedChecksum.isNotEmpty && checksumFor(rawJson) == expectedChecksum;

  static bool _isCorruption(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('sqlite_corrupt') ||
        message.contains('sqlite_notadb') ||
        message.contains('database disk image is malformed') ||
        message.contains('database malformed') ||
        message.contains('file is not a database') ||
        message.contains('database corrupt');
  }

  Future<bool> _recoverCorruptDatabase(
    Object error,
    StackTrace stackTrace,
  ) async {
    if (!_isCorruption(error)) return false;
    final path = p.join(await getDatabasesPath(), databaseName);
    AppLogger.I.warn(
      'ScheduleCache',
      'schedule cache operation detected corruption; rebuilding database',
      error: error,
      stackTrace: stackTrace,
      fields: const {'event': 'schedule_cache_database_recovery'},
    );
    await _database?.close();
    _database = null;
    _opening = null;
    await deleteDatabase(path);
    await _db;
    return true;
  }
}
