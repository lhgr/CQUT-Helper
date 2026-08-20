import 'dart:convert';

import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleMessageRecord {
  final String id;
  final String userId;
  final String yearTerm;
  final List<ScheduleWeekChange> changes;
  final DateTime createdAt;
  final bool read;

  const ScheduleMessageRecord({
    required this.id,
    required this.userId,
    required this.yearTerm,
    required this.changes,
    required this.createdAt,
    required this.read,
  });

  ScheduleMessageRecord copyWith({bool? read}) => ScheduleMessageRecord(
    id: id,
    userId: userId,
    yearTerm: yearTerm,
    changes: changes,
    createdAt: createdAt,
    read: read ?? this.read,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'userId': userId,
    'yearTerm': yearTerm,
    'createdAt': createdAt.toIso8601String(),
    'read': read,
    'changes': changes
        .map((change) => {'weekNum': change.weekNum, 'lines': change.lines})
        .toList(growable: false),
  };

  factory ScheduleMessageRecord.fromJson(Map<String, dynamic> json) {
    final changes = <ScheduleWeekChange>[];
    final rawChanges = json['changes'];
    if (rawChanges is List) {
      for (final raw in rawChanges) {
        if (raw is! Map) continue;
        final map = raw.cast<String, dynamic>();
        changes.add(
          ScheduleWeekChange(
            weekNum: (map['weekNum'] ?? '').toString(),
            lines:
                (map['lines'] as List?)
                    ?.map((line) => line.toString())
                    .toList(growable: false) ??
                const [],
          ),
        );
      }
    }
    return ScheduleMessageRecord(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? '').toString(),
      yearTerm: (json['yearTerm'] ?? '').toString(),
      changes: changes,
      createdAt:
          DateTime.tryParse((json['createdAt'] ?? '').toString())?.toLocal() ??
          DateTime.fromMillisecondsSinceEpoch(0),
      read: json['read'] == true,
    );
  }
}

class ScheduleMessageCenterManager {
  static const int maxRecords = 100;
  static final ValueNotifier<int> epoch = ValueNotifier<int>(0);

  static String _key(String userId) => 'schedule_message_history_v1_$userId';

  static Future<List<ScheduleMessageRecord>> load(String userId) async {
    final normalized = userId.trim();
    if (normalized.isEmpty) return const [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(normalized));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      final records = decoded
          .whereType<Map>()
          .map(
            (item) =>
                ScheduleMessageRecord.fromJson(item.cast<String, dynamic>()),
          )
          .where((record) => record.id.isNotEmpty)
          .toList(growable: false);
      records.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return records;
    } catch (_) {
      return const [];
    }
  }

  static Future<void> appendChanges({
    required String userId,
    required String yearTerm,
    required List<ScheduleWeekChange> changes,
  }) async {
    final normalized = userId.trim();
    if (normalized.isEmpty || changes.isEmpty) return;
    final now = DateTime.now();
    final signature = _signature(yearTerm, changes);
    final current = await load(normalized);
    final duplicate = current.any(
      (record) =>
          now.difference(record.createdAt).abs() <
              const Duration(minutes: 10) &&
          _signature(record.yearTerm, record.changes) == signature,
    );
    if (duplicate) return;
    final record = ScheduleMessageRecord(
      id: '${now.microsecondsSinceEpoch}_${signature.hashCode & 0x7fffffff}',
      userId: normalized,
      yearTerm: yearTerm.trim(),
      changes: changes,
      createdAt: now,
      read: false,
    );
    await _save(normalized, [record, ...current].take(maxRecords).toList());
  }

  static Future<void> markAllRead(String userId) async {
    final current = await load(userId);
    if (current.isEmpty || current.every((record) => record.read)) return;
    await _save(
      userId.trim(),
      current.map((record) => record.copyWith(read: true)).toList(),
    );
  }

  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId.trim()));
    epoch.value++;
  }

  static Future<void> _save(
    String userId,
    List<ScheduleMessageRecord> records,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(userId),
      jsonEncode(records.map((record) => record.toJson()).toList()),
    );
    epoch.value++;
  }

  static String _signature(String yearTerm, List<ScheduleWeekChange> changes) {
    final parts =
        changes
            .map((change) => '${change.weekNum}:${change.lines.join('|')}')
            .toList(growable: false)
          ..sort();
    return '${yearTerm.trim()}::${parts.join('||')}';
  }
}
