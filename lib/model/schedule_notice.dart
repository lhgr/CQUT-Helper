import 'dart:convert';
import 'package:crypto/crypto.dart';

class ScheduleNotice {
  final String noticeId;
  final String status;
  final String publishedAt;
  final String title;
  final String content;
  final String? courseName;
  final String? teacher;
  final String? originalTime;
  final String? originalClassroom;
  final String? adjustedTime;
  final String? adjustedClassroom;

  const ScheduleNotice({
    required this.noticeId,
    required this.status,
    required this.publishedAt,
    required this.title,
    required this.content,
    required this.courseName,
    required this.teacher,
    required this.originalTime,
    required this.originalClassroom,
    required this.adjustedTime,
    required this.adjustedClassroom,
  });

  factory ScheduleNotice.fromJson(Map<String, dynamic> json) {
    String norm(dynamic v) => (v ?? '').toString().trim();
    String? normNullable(dynamic v) {
      final s = norm(v);
      return s.isEmpty ? null : s;
    }

    final rawId = norm(json['notice_id']);
    final fallback = sha256
        .convert(utf8.encode('${norm(json['title'])}|${norm(json['published_at'])}'))
        .toString();
    return ScheduleNotice(
      noticeId: rawId.isEmpty ? fallback : rawId,
      status: norm(json['status']),
      publishedAt: norm(json['published_at']),
      title: norm(json['title']),
      content: norm(json['content']),
      courseName: normNullable(json['course_name']),
      teacher: normNullable(json['teacher']),
      originalTime: normNullable(json['original_time']),
      originalClassroom: normNullable(json['original_classroom']),
      adjustedTime: normNullable(json['adjusted_time']),
      adjustedClassroom: normNullable(json['adjusted_classroom']),
    );
  }

  String versionHash() {
    final raw = json.encode({
      'noticeId': noticeId,
      'status': status,
      'publishedAt': publishedAt,
      'title': title,
      'content': content,
      'courseName': courseName,
      'teacher': teacher,
      'originalTime': originalTime,
      'originalClassroom': originalClassroom,
      'adjustedTime': adjustedTime,
      'adjustedClassroom': adjustedClassroom,
    });
    return sha256.convert(utf8.encode(raw)).toString();
  }
}

class ScheduleNoticePollData {
  final String env;
  final String generatedAt;
  final List<ScheduleNotice> notices;

  const ScheduleNoticePollData({
    required this.env,
    required this.generatedAt,
    required this.notices,
  });
}
