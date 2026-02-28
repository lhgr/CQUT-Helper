import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/utils/schedule_date.dart';

enum CourseReminderSoundMode { silent, vibrate }

class CourseReminderSettings {
  final bool enabled;
  final int advanceMinutes;
  final bool autoSwitchSoundMode;
  final CourseReminderSoundMode soundMode;
  final int daysAhead;

  const CourseReminderSettings({
    required this.enabled,
    required this.advanceMinutes,
    required this.autoSwitchSoundMode,
    required this.soundMode,
    required this.daysAhead,
  });

  CourseReminderSettings copyWith({
    bool? enabled,
    int? advanceMinutes,
    bool? autoSwitchSoundMode,
    CourseReminderSoundMode? soundMode,
    int? daysAhead,
  }) {
    return CourseReminderSettings(
      enabled: enabled ?? this.enabled,
      advanceMinutes: advanceMinutes ?? this.advanceMinutes,
      autoSwitchSoundMode: autoSwitchSoundMode ?? this.autoSwitchSoundMode,
      soundMode: soundMode ?? this.soundMode,
      daysAhead: daysAhead ?? this.daysAhead,
    );
  }
}

class PlannedCourseReminder {
  final String key;
  final DateTime fireAt;
  final DateTime classStartAt;
  final String courseName;
  final String location;
  final String teacher;
  final int startSession;
  final int endSession;
  final bool autoSwitchSoundMode;
  final CourseReminderSoundMode soundMode;

  const PlannedCourseReminder({
    required this.key,
    required this.fireAt,
    required this.classStartAt,
    required this.courseName,
    required this.location,
    required this.teacher,
    required this.startSession,
    required this.endSession,
    required this.autoSwitchSoundMode,
    required this.soundMode,
  });
}

class CourseReminderPlanner {
  static List<PlannedCourseReminder> plan({
    required DateTime now,
    required CourseReminderSettings settings,
    required List<ScheduleData> candidateWeeks,
    required List<CampusTimeInfo>? timeInfoList,
  }) {
    if (!settings.enabled) return const [];
    final daysAhead = settings.daysAhead.clamp(0, 14);
    if (daysAhead <= 0) return const [];

    final today = DateTime(now.year, now.month, now.day);
    final candidates = <PlannedCourseReminder>[];

    for (int offsetDays = 0; offsetDays <= daysAhead; offsetDays++) {
      final day = today.add(Duration(days: offsetDays));

      final week = candidateWeeks.firstWhere(
        (w) => ScheduleDate.dataCoversDate(w, day),
        orElse: () => ScheduleData(),
      );
      if (week.weekDayList == null || week.weekDayList!.isEmpty) continue;
      if (week.eventList == null || week.eventList!.isEmpty) continue;

      final weekday = day.weekday;
      final weekDayDate = _dateForWeekday(week, weekday, reference: day);
      if (weekDayDate == null) continue;
      if (!_sameDate(weekDayDate, day)) continue;

      final grouped = _groupEventsForDay(week.eventList!, weekday);
      for (final g in grouped) {
        final startAt = _startDateTimeForSession(
          date: day,
          sessionNum: g.startSession,
          timeInfoList: timeInfoList,
        );
        if (startAt == null) continue;

        final fireAt = startAt.subtract(Duration(minutes: settings.advanceMinutes));
        if (!fireAt.isAfter(now)) continue;
        candidates.add(
          PlannedCourseReminder(
            key: g.key,
            fireAt: fireAt,
            classStartAt: startAt,
            courseName: g.courseName,
            location: g.location,
            teacher: g.teacher,
            startSession: g.startSession,
            endSession: g.endSession,
            autoSwitchSoundMode: settings.autoSwitchSoundMode,
            soundMode: settings.soundMode,
          ),
        );
      }
    }

    candidates.sort((a, b) => a.fireAt.compareTo(b.fireAt));
    return candidates;
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime? _dateForWeekday(
    ScheduleData data,
    int weekday, {
    required DateTime reference,
  }) {
    final dayList = data.weekDayList;
    if (dayList == null || dayList.isEmpty) return null;

    for (final item in dayList) {
      final wd = _parseWeekday(item.weekDay);
      if (wd == null || wd != weekday) continue;
      final d = ScheduleDate.tryParseWeekDate(item.weekDate, reference: reference);
      if (d != null) return d;
    }

    return null;
  }

  static int? _parseWeekday(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    final n = int.tryParse(s);
    if (n != null && n >= 1 && n <= 7) return n;
    switch (s) {
      case '周一':
      case '星期一':
      case '一':
        return DateTime.monday;
      case '周二':
      case '星期二':
      case '二':
        return DateTime.tuesday;
      case '周三':
      case '星期三':
      case '三':
        return DateTime.wednesday;
      case '周四':
      case '星期四':
      case '四':
        return DateTime.thursday;
      case '周五':
      case '星期五':
      case '五':
        return DateTime.friday;
      case '周六':
      case '星期六':
      case '六':
        return DateTime.saturday;
      case '周日':
      case '星期日':
      case '星期天':
      case '日':
      case '天':
        return DateTime.sunday;
    }
    return null;
  }

  static DateTime? _startDateTimeForSession({
    required DateTime date,
    required int sessionNum,
    required List<CampusTimeInfo>? timeInfoList,
  }) {
    if (sessionNum <= 0) return null;
    String? start;
    if (timeInfoList != null) {
      try {
        start =
            timeInfoList.firstWhere((e) => e.sessionNum == sessionNum).startTime;
      } catch (_) {}
    }
    if (start == null || start.trim().isEmpty) return null;
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(start.trim());
    if (match == null) return null;
    final h = int.tryParse(match.group(1)!) ?? -1;
    final m = int.tryParse(match.group(2)!) ?? -1;
    if (h < 0 || h > 23 || m < 0 || m > 59) return null;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  static List<_DayCourseGroup> _groupEventsForDay(
    List<EventItem> events,
    int weekday,
  ) {
    final segments = <String, List<_DayCourseSegment>>{};

    for (final e in events) {
      final wd = int.tryParse((e.weekDay ?? '').trim());
      if (wd == null || wd != weekday) continue;
      final start = int.tryParse((e.sessionStart ?? '').trim());
      final last = int.tryParse((e.sessionLast ?? '').trim());
      if (start == null || start <= 0) continue;
      if (last == null || last <= 0) continue;
      final end = start + last - 1;

      final baseKey = _baseKeyForEvent(e);
      final list = segments.putIfAbsent(baseKey, () => <_DayCourseSegment>[]);
      list.add(
        _DayCourseSegment(
          startSession: start,
          endSession: end,
          courseName: (e.eventName ?? '').trim(),
          location: (e.address ?? '').trim(),
          teacher: (e.memberName ?? '').trim(),
        ),
      );
    }

    final groups = <_DayCourseGroup>[];

    for (final entry in segments.entries) {
      final baseKey = entry.key;
      final list = entry.value;
      list.sort((a, b) => a.startSession.compareTo(b.startSession));

      _DayCourseGroup? current;
      for (final seg in list) {
        if (current == null) {
          current = _DayCourseGroup(
            key: '$baseKey|s:${seg.startSession}',
            courseName: seg.courseName,
            location: seg.location,
            teacher: seg.teacher,
            startSession: seg.startSession,
            endSession: seg.endSession,
          );
          continue;
        }

        final adjacentOrOverlap = seg.startSession <= current.endSession + 1;
        if (adjacentOrOverlap) {
          if (seg.endSession > current.endSession) {
            current.endSession = seg.endSession;
          }
          if (current.courseName.isEmpty && seg.courseName.isNotEmpty) {
            current.courseName = seg.courseName;
          }
          if (current.location.isEmpty && seg.location.isNotEmpty) {
            current.location = seg.location;
          }
          if (current.teacher.isEmpty && seg.teacher.isNotEmpty) {
            current.teacher = seg.teacher;
          }
          continue;
        }

        groups.add(current);
        current = _DayCourseGroup(
          key: '$baseKey|s:${seg.startSession}',
          courseName: seg.courseName,
          location: seg.location,
          teacher: seg.teacher,
          startSession: seg.startSession,
          endSession: seg.endSession,
        );
      }

      if (current != null) groups.add(current);
    }

    return groups;
  }

  static String _baseKeyForEvent(EventItem e) {
    final id = (e.eventID ?? '').trim();
    if (id.isNotEmpty) return 'id:$id';

    final name = (e.eventName ?? '').trim();
    final addr = (e.address ?? '').trim();
    final teacher = (e.memberName ?? '').trim();
    final dupType = (e.duplicateGroupType ?? '').trim();
    final dup = e.duplicateGroup?.toString() ?? '';

    return 'n:$name|a:$addr|t:$teacher|dt:$dupType|dg:$dup';
  }
}

class _DayCourseGroup {
  final String key;
  String courseName;
  String location;
  String teacher;
  int startSession;
  int endSession;

  _DayCourseGroup({
    required this.key,
    required this.courseName,
    required this.location,
    required this.teacher,
    required this.startSession,
    required this.endSession,
  });
}

class _DayCourseSegment {
  final int startSession;
  final int endSession;
  final String courseName;
  final String location;
  final String teacher;

  _DayCourseSegment({
    required this.startSession,
    required this.endSession,
    required this.courseName,
    required this.location,
    required this.teacher,
  });
}
