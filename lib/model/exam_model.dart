class ExamRecord {
  const ExamRecord({
    required this.key,
    required this.courseName,
    required this.timeText,
    required this.campus,
    required this.building,
    required this.room,
    this.startAt,
    this.endAt,
  });

  final String key;
  final String courseName;
  final String timeText;
  final String campus;
  final String building;
  final String room;
  final DateTime? startAt;
  final DateTime? endAt;

  String get location => [
    campus,
    building,
    room,
  ].where((part) => part.trim().isNotEmpty).join(' · ');
  bool get hasValidTime =>
      startAt != null && endAt != null && endAt!.isAfter(startAt!);
  DateTime? get schoolStartAt => startAt?.toUtc().add(const Duration(hours: 8));
  DateTime? get schoolEndAt => endAt?.toUtc().add(const Duration(hours: 8));

  factory ExamRecord.fromJson(Map<String, dynamic> json) {
    String value(String key) => (json[key] ?? '').toString().trim();
    if (value('key').isEmpty || value('course_name').isEmpty) {
      throw const FormatException('考试条目缺少名称或标识');
    }
    return ExamRecord(
      key: value('key'),
      courseName: value('course_name'),
      timeText: value('time_text'),
      campus: value('campus'),
      building: value('building'),
      room: value('room'),
      startAt: DateTime.tryParse(value('start_at')),
      endAt: DateTime.tryParse(value('end_at')),
    );
  }

  Map<String, dynamic> toJson() => {
    'key': key,
    'course_name': courseName,
    'time_text': timeText,
    'campus': campus,
    'building': building,
    'room': room,
    'start_at': startAt?.toIso8601String(),
    'end_at': endAt?.toIso8601String(),
  };
}

class ExamSnapshot {
  const ExamSnapshot({
    required this.generatedAt,
    required this.fetchedAt,
    required this.exams,
  });
  final DateTime generatedAt;
  final DateTime fetchedAt;
  final List<ExamRecord> exams;

  factory ExamSnapshot.fromJson(
    Map<String, dynamic> json, {
    DateTime? fetchedAt,
  }) {
    final generated = DateTime.tryParse(
      (json['generated_at'] ?? '').toString(),
    );
    final fetched =
        fetchedAt ?? DateTime.tryParse((json['fetched_at'] ?? '').toString());
    final records = json['exams'];
    if (json['exams_complete'] != true ||
        generated == null ||
        fetched == null ||
        records is! List) {
      throw const FormatException('考试数据不完整');
    }
    return ExamSnapshot(
      generatedAt: generated,
      fetchedAt: fetched,
      exams: List.unmodifiable(
        records.map((item) {
          if (item is! Map) throw const FormatException('考试条目格式无效');
          return ExamRecord.fromJson(item.cast<String, dynamic>());
        }),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'generated_at': generatedAt.toIso8601String(),
    'fetched_at': fetchedAt.toIso8601String(),
    'exams_complete': true,
    'exams': exams.map((exam) => exam.toJson()).toList(),
  };
}
