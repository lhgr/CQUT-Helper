import 'dart:convert';
import 'dart:io';

import 'package:cqut/utils/app_logger.dart';
import 'package:cqut/utils/course_notebook_key_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CourseNoteImage {
  final String id;
  final String path;
  final int createdAt;
  final String displayName;

  CourseNoteImage({
    required this.id,
    required this.path,
    required this.createdAt,
    required this.displayName,
  });

  factory CourseNoteImage.fromJson(Map<String, dynamic> json) {
    return CourseNoteImage(
      id: (json['id'] ?? '').toString(),
      path: (json['path'] ?? '').toString(),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
      displayName: (json['displayName'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'path': path,
      'createdAt': createdAt,
      'displayName': displayName,
    };
  }

  CourseNoteImage copyWith({String? displayName}) {
    return CourseNoteImage(
      id: id,
      path: path,
      createdAt: createdAt,
      displayName: displayName ?? this.displayName,
    );
  }
}

class CourseNotebookRecord {
  final String courseName;
  final String courseKey;
  final String? yearTerm;
  final String text;
  final List<CourseNoteImage> images;
  final int updatedAt;

  CourseNotebookRecord({
    required this.courseName,
    required this.courseKey,
    required this.yearTerm,
    required this.text,
    required this.images,
    required this.updatedAt,
  });

  factory CourseNotebookRecord.empty({
    required String courseName,
    required String courseKey,
    required String? yearTerm,
  }) {
    return CourseNotebookRecord(
      courseName: courseName,
      courseKey: courseKey,
      yearTerm: yearTerm,
      text: '',
      images: const [],
      updatedAt: 0,
    );
  }

  factory CourseNotebookRecord.fromJson(Map<String, dynamic> json) {
    final imageList = (json['images'] as List?)
            ?.whereType<Map>()
            .map((e) => CourseNoteImage.fromJson(e.cast<String, dynamic>()))
            .toList() ??
        const <CourseNoteImage>[];
    return CourseNotebookRecord(
      courseName: normalizeCourseName(json['courseName']?.toString()),
      courseKey: (json['courseKey'] ?? '').toString(),
      yearTerm: (json['yearTerm'] ?? '').toString().trim().isEmpty
          ? null
          : json['yearTerm'].toString().trim(),
      text: (json['text'] ?? '').toString(),
      images: imageList,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'courseName': courseName,
      'courseKey': courseKey,
      'yearTerm': yearTerm,
      'text': text,
      'images': images.map((e) => e.toJson()).toList(),
      'updatedAt': updatedAt,
    };
  }

  CourseNotebookRecord copyWith({
    String? text,
    List<CourseNoteImage>? images,
    int? updatedAt,
  }) {
    return CourseNotebookRecord(
      courseName: courseName,
      courseKey: courseKey,
      yearTerm: yearTerm,
      text: text ?? this.text,
      images: images ?? this.images,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class CourseNotebookManager {
  CourseNotebookManager._internal();

  static final CourseNotebookManager I = CourseNotebookManager._internal();

  static const String _prefsVersion = 'v1';

  Future<String> buildCourseKey({
    required String courseName,
    String? yearTerm,
  }) async {
    return buildCourseNotebookKey(
      courseName: courseName,
      yearTerm: yearTerm,
    );
  }

  Future<CourseNotebookRecord> loadRecord({
    required String courseName,
    String? yearTerm,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _currentUserId(prefs);
    final key = await buildCourseKey(courseName: courseName, yearTerm: yearTerm);
    final all = _decodeAllRecords(prefs.getString(_prefsKey(userId)));
    final existing = all[key];
    if (existing == null) {
      return CourseNotebookRecord.empty(
        courseName: normalizeCourseName(courseName),
        courseKey: key,
        yearTerm: yearTerm?.trim(),
      );
    }
    return existing;
  }

  Future<void> saveText({
    required String courseName,
    String? yearTerm,
    required String text,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _currentUserId(prefs);
    final key = await buildCourseKey(courseName: courseName, yearTerm: yearTerm);
    final all = _decodeAllRecords(prefs.getString(_prefsKey(userId)));
    final base = all[key] ??
        CourseNotebookRecord.empty(
          courseName: normalizeCourseName(courseName),
          courseKey: key,
          yearTerm: yearTerm?.trim(),
        );
    all[key] = base.copyWith(
      text: text,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    await prefs.setString(_prefsKey(userId), _encodeAllRecords(all));
  }

  Future<CourseNotebookRecord> saveImages({
    required String courseName,
    String? yearTerm,
    required List<CourseNoteImage> images,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = _currentUserId(prefs);
    final key = await buildCourseKey(courseName: courseName, yearTerm: yearTerm);
    final all = _decodeAllRecords(prefs.getString(_prefsKey(userId)));
    final base = all[key] ??
        CourseNotebookRecord.empty(
          courseName: normalizeCourseName(courseName),
          courseKey: key,
          yearTerm: yearTerm?.trim(),
        );
    final updated = base.copyWith(
      images: images,
      updatedAt: DateTime.now().millisecondsSinceEpoch,
    );
    all[key] = updated;
    await prefs.setString(_prefsKey(userId), _encodeAllRecords(all));
    return updated;
  }

  Future<void> deleteRecordImageFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      AppLogger.I.warn('CourseNotebook', 'delete_image_failed', fields: {
        'error': e.toString(),
      });
    }
  }

  Future<Directory> ensureCourseImageDir({
    required String courseName,
    String? yearTerm,
  }) async {
    final key = await buildCourseKey(courseName: courseName, yearTerm: yearTerm);
    final docs = await getApplicationDocumentsDirectory();
    final safeDirName = _sanitizeDirName(key);
    final dir = Directory(
      '${docs.path}${Platform.pathSeparator}course_notebook${Platform.pathSeparator}$safeDirName',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _currentUserId(SharedPreferences prefs) {
    final raw = (prefs.getString('account') ?? '').trim();
    if (raw.isEmpty) {
      return 'guest';
    }
    return raw;
  }

  String _prefsKey(String userId) => 'course_notebook_${_prefsVersion}_$userId';

  Map<String, CourseNotebookRecord> _decodeAllRecords(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, CourseNotebookRecord>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return <String, CourseNotebookRecord>{};
      }
      final map = <String, CourseNotebookRecord>{};
      decoded.forEach((key, value) {
        if (value is Map<String, dynamic>) {
          map[key] = CourseNotebookRecord.fromJson(value);
        } else if (value is Map) {
          map[key] = CourseNotebookRecord.fromJson(value.cast<String, dynamic>());
        }
      });
      return map;
    } catch (_) {
      return <String, CourseNotebookRecord>{};
    }
  }

  String _encodeAllRecords(Map<String, CourseNotebookRecord> records) {
    final payload = <String, dynamic>{};
    records.forEach((key, value) {
      payload[key] = value.toJson();
    });
    return jsonEncode(payload);
  }

  String _sanitizeDirName(String raw) {
    final replaced = raw.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return replaced.replaceAll(' ', '_');
  }
}
