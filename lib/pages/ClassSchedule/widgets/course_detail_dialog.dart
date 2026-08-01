import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter/material.dart';
import 'package:cqut_helper/utils/schedule_ics_service.dart';

void showCourseDetailDialog(
  BuildContext context, {
  required String courseName,
  required List<EventItem> events,
  Color? closeButtonColor,
  DateTime? eventDate,
  List<CampusTimeInfo>? timeInfoList,
}) {
  final normalizedName = courseName.trim().isEmpty
      ? '未命名课程'
      : courseName.trim();
  final teachers =
      events
          .map((e) => _safeValue(e.memberName))
          .toSet()
          .toList(growable: false)
        ..sort();
  final classrooms =
      events.map((e) => _safeValue(e.address)).toSet().toList(growable: false)
        ..sort();
  final weekCovers =
      events.map((e) => _safeValue(e.weekCover)).toSet().toList(growable: false)
        ..sort();
  final sessions = _buildSessionLines(events);
  final notes = events
      .map((event) => (event.note ?? '').trim())
      .where((note) => note.isNotEmpty)
      .toSet()
      .toList(growable: false);
  final calendarRange = eventDate == null || events.isEmpty
      ? null
      : _calendarRange(eventDate, events.first, timeInfoList ?? const []);

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final buttonColor = closeButtonColor;
      final onButtonColor = buttonColor == null
          ? null
          : _onButtonColor(buttonColor);
      final screenWidth = MediaQuery.sizeOf(dialogContext).width;
      final dialogWidth = (screenWidth - 48).clamp(280.0, 360.0);
      return AlertDialog(
        title: Text(
          normalizedName,
          style: Theme.of(dialogContext).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        content: SizedBox(
          width: dialogWidth,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(
                  dialogContext,
                  Icons.person_outline,
                  "教师",
                  teachers.join("、"),
                ),
                _buildDetailRow(
                  dialogContext,
                  Icons.room_outlined,
                  "教室",
                  classrooms.join("、"),
                ),
                _buildDetailRow(
                  dialogContext,
                  Icons.calendar_today_outlined,
                  "周次",
                  weekCovers.join("、"),
                ),
                _buildDetailRow(
                  dialogContext,
                  Icons.access_time,
                  "节次",
                  sessions.map((e) => e.text).join('\n'),
                ),
                if (notes.isNotEmpty)
                  _buildDetailRow(
                    dialogContext,
                    Icons.notes,
                    '备注',
                    notes.join('\n'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (calendarRange != null)
            TextButton.icon(
              onPressed: () async {
                final event = events.first;
                final ok = await ScheduleIcsService.addToSystemCalendar(
                  title: normalizedName,
                  description: notes.join('\n'),
                  location: (event.address ?? '').trim(),
                  start: calendarRange.$1,
                  end: calendarRange.$2,
                );
                if (!ok || !dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
              },
              icon: const Icon(Icons.event_available_outlined),
              label: const Text('加入日历'),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: buttonColor,
              foregroundColor: onButtonColor,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text("关闭"),
          ),
        ],
      );
    },
  );
}

(DateTime, DateTime)? _calendarRange(
  DateTime date,
  EventItem event,
  List<CampusTimeInfo> timeInfo,
) {
  final startSession = _sessionStartForSort(event);
  final last =
      int.tryParse((event.sessionLast ?? '').trim()) ??
      (event.sessionList ?? const <String>[]).length.clamp(1, 12);
  final endSession = startSession + last - 1;
  CampusTimeInfo? startInfo;
  CampusTimeInfo? endInfo;
  for (final info in timeInfo) {
    if (info.sessionNum == startSession) startInfo = info;
    if (info.sessionNum == endSession) endInfo = info;
  }
  final startClock = _clock(startInfo?.startTime);
  final endClock = _clock(endInfo?.endTime);
  if (startClock == null || endClock == null) return null;
  final start = DateTime(
    date.year,
    date.month,
    date.day,
    startClock.$1,
    startClock.$2,
  );
  final end = DateTime(
    date.year,
    date.month,
    date.day,
    endClock.$1,
    endClock.$2,
  );
  return (start, end);
}

(int, int)? _clock(String? value) {
  final match = RegExp(r'(\d{1,2})\s*[:：]\s*(\d{1,2})').firstMatch(value ?? '');
  if (match == null) return null;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) return null;
  return (hour, minute);
}

Widget _buildDetailRow(
  BuildContext context,
  IconData icon,
  String label,
  String value,
) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              Text(
                value.isEmpty ? "未知" : value,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

List<_SessionLine> _buildSessionLines(List<EventItem> events) {
  final seen = <String>{};
  final result = <_SessionLine>[];
  for (final event in events) {
    final weekDayRaw = (event.weekDay ?? '').trim();
    final weekDay = int.tryParse(weekDayRaw) ?? 0;
    final weekDayText = _weekdayText(weekDayRaw);
    final session = _sessionText(event);
    final start = _sessionStartForSort(event);
    final weekCover = _safeValue(event.weekCover);
    final text = '$weekDayText $session（$weekCover）';
    if (!seen.add(text)) {
      continue;
    }
    result.add(_SessionLine(text: text, weekDay: weekDay, start: start));
  }
  result.sort((a, b) {
    final byWeekDay = a.weekDay.compareTo(b.weekDay);
    if (byWeekDay != 0) return byWeekDay;
    final byStart = a.start.compareTo(b.start);
    if (byStart != 0) return byStart;
    return a.text.compareTo(b.text);
  });
  return result;
}

int _sessionStartForSort(EventItem event) {
  final start = int.tryParse((event.sessionStart ?? '').trim());
  if (start != null && start > 0) return start;
  var min = 999;
  for (final raw in (event.sessionList ?? const <String>[])) {
    final n = int.tryParse(raw.trim());
    if (n != null && n > 0 && n < min) {
      min = n;
    }
  }
  return min == 999 ? 999 : min;
}

String _sessionText(EventItem event) {
  final start = int.tryParse((event.sessionStart ?? '').trim());
  final last = int.tryParse((event.sessionLast ?? '').trim());
  if (start != null && last != null && start > 0 && last > 0) {
    final end = start + last - 1;
    return '$start-$end节';
  }
  final sessions = (event.sessionList ?? const <String>[])
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
  if (sessions.isEmpty) return '未知';
  return '${sessions.join(",")}节';
}

String _weekdayText(String? weekDay) {
  switch ((weekDay ?? '').trim()) {
    case '1':
      return '周一';
    case '2':
      return '周二';
    case '3':
      return '周三';
    case '4':
      return '周四';
    case '5':
      return '周五';
    case '6':
      return '周六';
    case '7':
      return '周日';
    default:
      return '未知';
  }
}

String _safeValue(String? raw) {
  final v = (raw ?? '').trim();
  return v.isEmpty ? '未知' : v;
}

Color _onButtonColor(Color color) {
  const white = Colors.white;
  const black = Colors.black;
  final onWhite = _contrastRatio(color, white);
  final onBlack = _contrastRatio(color, black);
  return onWhite >= onBlack ? white : black;
}

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + 0.05) / (darker + 0.05);
}

class _SessionLine {
  final String text;
  final int weekDay;
  final int start;

  _SessionLine({
    required this.text,
    required this.weekDay,
    required this.start,
  });
}
