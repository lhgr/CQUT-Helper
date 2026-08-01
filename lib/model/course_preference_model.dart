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
