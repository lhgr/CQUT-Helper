import 'package:cqut/model/schedule_notice.dart';

class ScheduleNoticeImpact {
  final String noticeId;
  final String noticeVersion;
  final Set<String> weeks;
  final Set<String> keys;
  final String line;

  const ScheduleNoticeImpact({
    required this.noticeId,
    required this.noticeVersion,
    required this.weeks,
    required this.keys,
    required this.line,
  });

  Map<String, dynamic> toJson() {
    return {
      'noticeId': noticeId,
      'noticeVersion': noticeVersion,
      'weeks': weeks.toList(),
      'keys': keys.toList(),
      'line': line,
    };
  }

  factory ScheduleNoticeImpact.fromJson(Map<String, dynamic> json) {
    Set<String> stringSet(dynamic raw) {
      if (raw is! List) return <String>{};
      return raw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toSet();
    }

    return ScheduleNoticeImpact(
      noticeId: (json['noticeId'] ?? '').toString().trim(),
      noticeVersion: (json['noticeVersion'] ?? '').toString().trim(),
      weeks: stringSet(json['weeks']),
      keys: stringSet(json['keys']),
      line: (json['line'] ?? '').toString().trim(),
    );
  }
}

class ScheduleNoticeParser {
  static final RegExp _weekReg = RegExp(r'第\s*(\d{1,2})(?:\s*[-~到至]\s*(\d{1,2}))?\s*周');
  static final RegExp _sessionReg = RegExp(r'第\s*(\d{1,2})(?:\s*[-~到至]\s*(\d{1,2}))?\s*节');
  static final RegExp _classReg = RegExp(r'([0-9A-Za-z\u4e00-\u9fa5]{2,20}班)');

  static ScheduleNoticeImpact parseImpact(ScheduleNotice notice) {
    final weekSources = <String>[
      notice.adjustedTime ?? '',
      notice.originalTime ?? '',
      notice.content,
      notice.title,
    ];
    final sessionSources = <String>[
      notice.adjustedTime ?? '',
      notice.originalTime ?? '',
      notice.content,
      notice.title,
    ];
    final classSources = <String>[
      notice.content,
      notice.title,
    ];

    final weeks = _parseWeeks(weekSources);
    final session = _parseSession(sessionSources);
    final className = _parseClassName(classSources);
    final normalizedWeeks = weeks.isEmpty ? <String>{'0'} : weeks;
    final keys = normalizedWeeks.map((w) => '$w-$className-$session').toSet();

    final course = notice.courseName ?? '未知课程';
    final teacher = notice.teacher ?? '未知教师';
    final line = '[$className][$session]$course($teacher)';

    return ScheduleNoticeImpact(
      noticeId: notice.noticeId,
      noticeVersion: notice.versionHash(),
      weeks: normalizedWeeks,
      keys: keys,
      line: line,
    );
  }

  static Set<String> _parseWeeks(List<String> sources) {
    final out = <String>{};
    for (final src in sources) {
      for (final m in _weekReg.allMatches(src)) {
        final start = int.tryParse(m.group(1) ?? '');
        final end = int.tryParse(m.group(2) ?? '');
        if (start == null) continue;
        if (end == null || end < start) {
          out.add('$start');
          continue;
        }
        for (int i = start; i <= end; i++) {
          out.add('$i');
        }
      }
    }
    return out;
  }

  static String _parseSession(List<String> sources) {
    for (final src in sources) {
      final m = _sessionReg.firstMatch(src);
      if (m == null) continue;
      final first = (m.group(1) ?? '').trim();
      final second = (m.group(2) ?? '').trim();
      if (first.isEmpty) continue;
      if (second.isEmpty) return '第$first节';
      return '第$first-$second节';
    }
    return '未知节次';
  }

  static String _parseClassName(List<String> sources) {
    for (final src in sources) {
      final m = _classReg.firstMatch(src);
      if (m == null) continue;
      final value = (m.group(1) ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    return '未知班级';
  }
}
