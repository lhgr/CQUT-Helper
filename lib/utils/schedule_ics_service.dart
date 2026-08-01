import 'dart:io';

import 'package:cqut_helper/manager/schedule_customization_manager.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class ScheduleIcsService {
  static const MethodChannel _interop = MethodChannel('cqut/schedule_interop');
  static const MethodChannel _downloads = MethodChannel('cqut/downloads');

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
}
