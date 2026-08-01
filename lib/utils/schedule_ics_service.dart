import 'dart:io';

import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/local_schedule_model.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ScheduleIcsImportResult {
  final List<LocalScheduleEvent> events;
  final int skipped;

  const ScheduleIcsImportResult({required this.events, required this.skipped});
}

class ScheduleIcsService {
  static const MethodChannel _interop = MethodChannel('cqut/schedule_interop');
  static const MethodChannel _downloads = MethodChannel('cqut/downloads');

  static Future<String?> pickIcsText() async {
    if (!Platform.isAndroid) return null;
    return _interop.invokeMethod<String>('pickIcs');
  }

  static ScheduleIcsImportResult parse({
    required String content,
    required String userId,
    required String yearTerm,
    required List<CampusTimeInfo> timeInfo,
  }) {
    final unfolded = content.replaceAll(RegExp(r'\r?\n[ \t]'), '');
    final lines = unfolded.split(RegExp(r'\r?\n'));
    final blocks = <Map<String, String>>[];
    Map<String, String>? current;
    for (final line in lines) {
      final normalized = line.trimRight();
      if (normalized == 'BEGIN:VEVENT') {
        current = <String, String>{};
        continue;
      }
      if (normalized == 'END:VEVENT') {
        if (current != null) blocks.add(current);
        current = null;
        continue;
      }
      if (current == null) continue;
      final colon = normalized.indexOf(':');
      if (colon <= 0) continue;
      final rawKey = normalized.substring(0, colon);
      final key = rawKey.split(';').first.toUpperCase();
      current[key] = _unescape(normalized.substring(colon + 1));
    }

    final clock = <int, ({int start, int end})>{};
    for (final info in timeInfo) {
      final num = info.sessionNum;
      final start = _minuteOfDay(info.startTime);
      final end = _minuteOfDay(info.endTime);
      if (num != null && start != null && end != null) {
        clock[num] = (start: start, end: end);
      }
    }

    final now = DateTime.now();
    final events = <LocalScheduleEvent>[];
    var skipped = 0;
    for (final block in blocks) {
      final start = _parseIcsDate(block['DTSTART']);
      if (start == null) {
        skipped++;
        continue;
      }
      final end = _parseIcsDate(block['DTEND']);
      final session = _matchSessionRange(start, end, clock);
      final title = (block['SUMMARY'] ?? '').trim();
      if (title.isEmpty) {
        skipped++;
        continue;
      }
      events.add(
        LocalScheduleEvent(
          id: ScheduleCustomizationManager.instance.newId(),
          userId: userId,
          yearTerm: yearTerm,
          title: title,
          teacher: '',
          location: (block['LOCATION'] ?? '').trim(),
          note: (block['DESCRIPTION'] ?? '').trim(),
          weeks: const <int>[],
          weekDay: start.weekday,
          startSession: session.$1,
          sessionCount: session.$2,
          specificDate: DateTime(start.year, start.month, start.day),
          reminderMinutes: null,
          colorIndex: null,
          source: LocalScheduleSource.ics,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return ScheduleIcsImportResult(events: events, skipped: skipped);
  }

  static String generate({
    required Iterable<ScheduleData> schedules,
    required List<CampusTimeInfo> timeInfo,
  }) {
    final clock = <int, ({String start, String end})>{};
    for (final info in timeInfo) {
      final num = info.sessionNum;
      final start = _normalizeClock(info.startTime);
      final end = _normalizeClock(info.endTime);
      if (num != null && start != null && end != null) {
        clock[num] = (start: start, end: end);
      }
    }
    final buffer = StringBuffer()
      ..writeln('BEGIN:VCALENDAR')
      ..writeln('VERSION:2.0')
      ..writeln('PRODID:-//CQUT Helper//Schedule//ZH-CN')
      ..writeln('CALSCALE:GREGORIAN')
      ..writeln('METHOD:PUBLISH')
      ..writeln('X-WR-CALNAME:CQUT 课表');
    final seen = <String>{};
    for (final schedule in schedules) {
      final dates = ScheduleCustomizationManager.scheduleDates(schedule);
      for (final event in schedule.eventList ?? const <EventItem>[]) {
        final weekday = int.tryParse((event.weekDay ?? '').trim());
        final date = weekday == null ? null : dates[weekday];
        if (date == null) continue;
        final startSession = _eventStart(event);
        final endSession = startSession + _eventCount(event) - 1;
        final startClock = clock[startSession]?.start ?? '080000';
        final endClock = clock[endSession]?.end ?? '090000';
        final identity =
            '${event.eventID}|${event.eventName}|${_date(date)}|$startSession';
        if (!seen.add(identity)) continue;
        final uidBase = '${identity.hashCode.abs()}-${_date(date)}@cqut-helper';
        final description = <String>[
          if ((event.memberName ?? '').trim().isNotEmpty)
            '教师：${event.memberName!.trim()}',
          if ((event.note ?? '').trim().isNotEmpty) event.note!.trim(),
        ].join(r'\n');
        buffer
          ..writeln('BEGIN:VEVENT')
          ..writeln('UID:$uidBase')
          ..writeln('DTSTAMP:${_utcStamp(DateTime.now().toUtc())}')
          ..writeln('DTSTART:${_date(date)}T$startClock')
          ..writeln('DTEND:${_date(date)}T$endClock')
          ..writeln('SUMMARY:${_escape(event.eventName ?? '课程')}')
          ..writeln('LOCATION:${_escape(event.address ?? '')}')
          ..writeln('DESCRIPTION:${_escape(description)}')
          ..writeln('END:VEVENT');
      }
    }
    buffer.writeln('END:VCALENDAR');
    return buffer.toString();
  }

  static Future<String> exportToDownloads({
    required String content,
    required String fileName,
  }) async {
    final temp = await getTemporaryDirectory();
    final file = File('${temp.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(content, flush: true);
    if (!Platform.isAndroid) return file.path;
    final result = await _downloads.invokeMapMethod<String, dynamic>(
      'exportToDownloads',
      {'srcPath': file.path, 'fileName': fileName, 'mimeType': 'text/calendar'},
    );
    return result?['path']?.toString() ?? file.path;
  }

  static Future<bool> addToSystemCalendar({
    required String title,
    required String description,
    required String location,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!Platform.isAndroid) return false;
    return await _interop.invokeMethod<bool>('addToCalendar', {
          'title': title,
          'description': description,
          'location': location,
          'beginMillis': start.millisecondsSinceEpoch,
          'endMillis': end.millisecondsSinceEpoch,
        }) ??
        false;
  }

  static (int, int) _matchSessionRange(
    DateTime start,
    DateTime? end,
    Map<int, ({int start, int end})> clock,
  ) {
    if (clock.isEmpty) return (1, 1);
    final startMinute = start.hour * 60 + start.minute;
    final endMinute = end == null
        ? startMinute + 60
        : end.hour * 60 + end.minute;
    var first = 1;
    var bestDistance = 1 << 30;
    for (final entry in clock.entries) {
      final distance = (entry.value.start - startMinute).abs();
      if (distance < bestDistance) {
        bestDistance = distance;
        first = entry.key;
      }
    }
    var last = first;
    for (final entry in clock.entries) {
      if (entry.key >= first && entry.value.end <= endMinute + 15) {
        last = entry.key;
      }
    }
    return (first, (last - first + 1).clamp(1, 12));
  }

  static DateTime? _parseIcsDate(String? raw) {
    final value = (raw ?? '').trim();
    if (value.length < 8) return null;
    final year = int.tryParse(value.substring(0, 4));
    final month = int.tryParse(value.substring(4, 6));
    final day = int.tryParse(value.substring(6, 8));
    if (year == null || month == null || day == null) return null;
    if (!value.contains('T')) return DateTime(year, month, day);
    final t = value.indexOf('T');
    final clock = value.substring(t + 1).replaceAll('Z', '');
    if (clock.length < 4) return DateTime(year, month, day);
    final hour = int.tryParse(clock.substring(0, 2)) ?? 0;
    final minute = int.tryParse(clock.substring(2, 4)) ?? 0;
    final second = clock.length >= 6
        ? int.tryParse(clock.substring(4, 6)) ?? 0
        : 0;
    final date = value.endsWith('Z')
        ? DateTime.utc(year, month, day, hour, minute, second).toLocal()
        : DateTime(year, month, day, hour, minute, second);
    return date;
  }

  static int? _minuteOfDay(String? raw) {
    final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{1,2})').firstMatch(raw ?? '');
    if (match == null) return null;
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || hour > 23 || minute > 59) return null;
    return hour * 60 + minute;
  }

  static String? _normalizeClock(String? raw) {
    final minute = _minuteOfDay(raw);
    if (minute == null) return null;
    return '${(minute ~/ 60).toString().padLeft(2, '0')}'
        '${(minute % 60).toString().padLeft(2, '0')}00';
  }

  static int _eventStart(EventItem event) {
    final direct = int.tryParse((event.sessionStart ?? '').trim());
    if (direct != null && direct > 0) return direct;
    final sessions = (event.sessionList ?? const <String>[])
        .map(int.tryParse)
        .whereType<int>()
        .where((e) => e > 0)
        .toList();
    return sessions.isEmpty ? 1 : sessions.reduce((a, b) => a < b ? a : b);
  }

  static int _eventCount(EventItem event) {
    final direct = int.tryParse((event.sessionLast ?? '').trim());
    if (direct != null && direct > 0) return direct;
    return (event.sessionList ?? const <String>[]).length.clamp(1, 12);
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}'
      '${value.month.toString().padLeft(2, '0')}'
      '${value.day.toString().padLeft(2, '0')}';

  static String _utcStamp(DateTime value) =>
      '${_date(value)}T'
      '${value.hour.toString().padLeft(2, '0')}'
      '${value.minute.toString().padLeft(2, '0')}'
      '${value.second.toString().padLeft(2, '0')}Z';

  static String _escape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('\n', r'\n')
      .replaceAll(',', r'\,')
      .replaceAll(';', r'\;');

  static String _unescape(String value) => value
      .replaceAll(r'\n', '\n')
      .replaceAll(r'\N', '\n')
      .replaceAll(r'\,', ',')
      .replaceAll(r'\;', ';')
      .replaceAll(r'\\', '\\');
}
