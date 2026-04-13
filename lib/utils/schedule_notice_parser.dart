import 'package:cqut_helper/model/schedule_notice.dart';

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
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet();
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
  static final RegExp _weekReg = RegExp(
    r'第\s*(\d{1,2})(?:\s*[-~到至]\s*(\d{1,2}))?\s*周',
  );
  static final RegExp _weekdayReg = RegExp(r'(星期[一二三四五六日天]|周[一二三四五六日天])');
  static final RegExp _sessionReg = RegExp(
    r'第\s*(\d{1,2})(?:\s*[-~到至]\s*(\d{1,2}))?\s*节',
  );
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
    final classSources = <String>[notice.content, notice.title];

    final weeks = _parseWeeks(weekSources);
    final session = _parseSession(sessionSources);
    final className = _parseClassName(classSources);
    final normalizedWeeks = weeks.isEmpty ? <String>{'0'} : weeks;
    final keys = normalizedWeeks.map((w) => '$w-$className-$session').toSet();

    final line = _buildNoticeLine(notice);

    return ScheduleNoticeImpact(
      noticeId: notice.noticeId,
      noticeVersion: notice.versionHash(),
      weeks: normalizedWeeks,
      keys: keys,
      line: line,
    );
  }

  static String _buildNoticeLine(ScheduleNotice notice) {
    final course = (notice.courseName ?? '').trim().isEmpty
        ? '未知课程'
        : notice.courseName!.trim();
    final from = _parseTimeSlot(notice.originalTime ?? '');
    final to = _parseTimeSlot(notice.adjustedTime ?? '');
    if (from == null || to == null) {
      return '调课通知信息不完整：**$course**课程（请在调课记录中查看详情）';
    }
    return '第${from.week}周${from.weekday}${from.session}节的**$course**课程调课到第${to.week}周${to.weekday}${to.session}节';
  }

  static ({String week, String weekday, String session})? _parseTimeSlot(
    String raw,
  ) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final weekMatch = _weekReg.firstMatch(text);
    final weekdayMatch = _weekdayReg.firstMatch(text);
    final sessionMatch = _sessionReg.firstMatch(text);
    final week = (weekMatch?.group(1) ?? '').trim();
    final weekday = (weekdayMatch?.group(1) ?? '').trim().replaceFirst('周', '星期');
    final sessionStart = (sessionMatch?.group(1) ?? '').trim();
    final sessionEnd = (sessionMatch?.group(2) ?? '').trim();
    if (week.isEmpty || weekday.isEmpty || sessionStart.isEmpty) {
      return null;
    }
    final session = sessionEnd.isEmpty
        ? '第$sessionStart'
        : '第$sessionStart-$sessionEnd';
    return (week: week, weekday: weekday, session: session);
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
