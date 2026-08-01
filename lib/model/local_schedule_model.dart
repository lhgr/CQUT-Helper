import 'dart:convert';

enum LocalScheduleSource { manual, ics }

class LocalScheduleEvent {
  final String id;
  final String userId;
  final String yearTerm;
  final String title;
  final String teacher;
  final String location;
  final String note;
  final List<int> weeks;
  final int weekDay;
  final int startSession;
  final int sessionCount;
  final DateTime? specificDate;
  final int? reminderMinutes;
  final int? colorIndex;
  final LocalScheduleSource source;
  final DateTime createdAt;
  final DateTime updatedAt;

  const LocalScheduleEvent({
    required this.id,
    required this.userId,
    required this.yearTerm,
    required this.title,
    required this.teacher,
    required this.location,
    required this.note,
    required this.weeks,
    required this.weekDay,
    required this.startSession,
    required this.sessionCount,
    required this.specificDate,
    required this.reminderMinutes,
    required this.colorIndex,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  bool appliesToWeek(int week, Iterable<DateTime> dates) {
    final date = specificDate;
    if (date != null) {
      return dates.any((candidate) => _sameDate(candidate, date));
    }
    return weeks.contains(week);
  }

  LocalScheduleEvent copyWith({
    String? title,
    String? teacher,
    String? location,
    String? note,
    List<int>? weeks,
    int? weekDay,
    int? startSession,
    int? sessionCount,
    DateTime? specificDate,
    bool clearSpecificDate = false,
    int? reminderMinutes,
    bool clearReminder = false,
    int? colorIndex,
    bool clearColor = false,
    DateTime? updatedAt,
  }) {
    return LocalScheduleEvent(
      id: id,
      userId: userId,
      yearTerm: yearTerm,
      title: title ?? this.title,
      teacher: teacher ?? this.teacher,
      location: location ?? this.location,
      note: note ?? this.note,
      weeks: weeks ?? this.weeks,
      weekDay: weekDay ?? this.weekDay,
      startSession: startSession ?? this.startSession,
      sessionCount: sessionCount ?? this.sessionCount,
      specificDate: clearSpecificDate
          ? null
          : specificDate ?? this.specificDate,
      reminderMinutes: clearReminder
          ? null
          : reminderMinutes ?? this.reminderMinutes,
      colorIndex: clearColor ? null : colorIndex ?? this.colorIndex,
      source: source,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toDatabaseMap() => {
    'id': id,
    'user_id': userId,
    'year_term': yearTerm,
    'title': title,
    'teacher': teacher,
    'location': location,
    'note': note,
    'weeks_json': jsonEncode(weeks),
    'week_day': weekDay,
    'start_session': startSession,
    'session_count': sessionCount,
    'specific_date': specificDate == null ? null : _dateKey(specificDate!),
    'reminder_minutes': reminderMinutes,
    'color_index': colorIndex,
    'source': source.name,
    'created_at': createdAt.millisecondsSinceEpoch,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory LocalScheduleEvent.fromDatabaseMap(Map<String, Object?> map) {
    final rawWeeks = jsonDecode((map['weeks_json'] as String?) ?? '[]');
    return LocalScheduleEvent(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      yearTerm: map['year_term'] as String,
      title: (map['title'] as String?) ?? '',
      teacher: (map['teacher'] as String?) ?? '',
      location: (map['location'] as String?) ?? '',
      note: (map['note'] as String?) ?? '',
      weeks: rawWeeks is List
          ? rawWeeks.whereType<num>().map((e) => e.toInt()).toList()
          : const <int>[],
      weekDay: (map['week_day'] as num?)?.toInt() ?? 1,
      startSession: (map['start_session'] as num?)?.toInt() ?? 1,
      sessionCount: (map['session_count'] as num?)?.toInt() ?? 1,
      specificDate: DateTime.tryParse((map['specific_date'] as String?) ?? ''),
      reminderMinutes: (map['reminder_minutes'] as num?)?.toInt(),
      colorIndex: (map['color_index'] as num?)?.toInt(),
      source: LocalScheduleSource.values.firstWhere(
        (value) => value.name == map['source'],
        orElse: () => LocalScheduleSource.manual,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (map['created_at'] as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class CoursePreference {
  final String userId;
  final String yearTerm;
  final String courseKey;
  final String? displayName;
  final String? teacher;
  final String? location;
  final String note;
  final bool hidden;
  final int? reminderMinutes;
  final int? colorIndex;
  final DateTime updatedAt;

  const CoursePreference({
    required this.userId,
    required this.yearTerm,
    required this.courseKey,
    required this.displayName,
    required this.teacher,
    required this.location,
    required this.note,
    required this.hidden,
    required this.reminderMinutes,
    required this.colorIndex,
    required this.updatedAt,
  });

  Map<String, Object?> toDatabaseMap() => {
    'user_id': userId,
    'year_term': yearTerm,
    'course_key': courseKey,
    'display_name': displayName,
    'teacher': teacher,
    'location': location,
    'note': note,
    'hidden': hidden ? 1 : 0,
    'reminder_minutes': reminderMinutes,
    'color_index': colorIndex,
    'updated_at': updatedAt.millisecondsSinceEpoch,
  };

  factory CoursePreference.fromDatabaseMap(Map<String, Object?> map) {
    return CoursePreference(
      userId: map['user_id'] as String,
      yearTerm: map['year_term'] as String,
      courseKey: map['course_key'] as String,
      displayName: map['display_name'] as String?,
      teacher: map['teacher'] as String?,
      location: map['location'] as String?,
      note: (map['note'] as String?) ?? '',
      hidden: ((map['hidden'] as num?)?.toInt() ?? 0) == 1,
      reminderMinutes: (map['reminder_minutes'] as num?)?.toInt(),
      colorIndex: (map['color_index'] as num?)?.toInt(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['updated_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

String localScheduleDateKey(DateTime value) => _dateKey(value);

bool localScheduleSameDate(DateTime a, DateTime b) => _sameDate(a, b);

String _dateKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

bool _sameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
