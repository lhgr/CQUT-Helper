import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:flutter/material.dart';

void showCourseDetailDialog(
  BuildContext context, {
  required String courseName,
  required List<EventItem> events,
  Color? closeButtonColor,
}) {
  final normalizedName = courseName.trim().isEmpty ? '未命名课程' : courseName.trim();
  final teachers =
      events.map((e) => _safeValue(e.memberName)).toSet().toList(growable: false)..sort();
  final classrooms =
      events.map((e) => _safeValue(e.address)).toSet().toList(growable: false)..sort();
  final weekCovers =
      events.map((e) => _safeValue(e.weekCover)).toSet().toList(growable: false)..sort();
  final sessions = _buildSessionLines(events);

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final buttonColor = closeButtonColor;
      final onButtonColor = buttonColor == null ? null : _onButtonColor(buttonColor);
      return AlertDialog(
        title: Text(
          normalizedName,
          style: Theme.of(dialogContext).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(dialogContext, Icons.person_outline, "教师", teachers.join("、")),
              _buildDetailRow(dialogContext, Icons.room_outlined, "教室", classrooms.join("、")),
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
            ],
          ),
        ),
        actions: [
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
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
              ),
              Text(value.isEmpty ? "未知" : value, style: Theme.of(context).textTheme.bodyMedium),
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
  final sessions =
      (event.sessionList ?? const <String>[])
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
