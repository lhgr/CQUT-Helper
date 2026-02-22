import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/model/schedule_week_change.dart';

List<ScheduleWeekChange> diffScheduleWeeks({
  required String weekNum,
  required ScheduleData before,
  required ScheduleData after,
  int maxLines = 30,
}) {
  final lines = diffScheduleWeekLines(
    before: before,
    after: after,
    maxLines: maxLines,
  );
  return [ScheduleWeekChange(weekNum: weekNum, lines: lines)];
}

List<String> diffScheduleWeekLines({
  required ScheduleData before,
  required ScheduleData after,
  int maxLines = 30,
}) {
  final beforeEvents = before.eventList ?? const <EventItem>[];
  final afterEvents = after.eventList ?? const <EventItem>[];

  final beforeMap = <String, EventItem>{};
  for (final e in beforeEvents) {
    _putUnique(beforeMap, _eventKey(e), e);
  }

  final afterMap = <String, EventItem>{};
  for (final e in afterEvents) {
    _putUnique(afterMap, _eventKey(e), e);
  }

  final keys = <String>{...beforeMap.keys, ...afterMap.keys}.toList()..sort();
  final out = <String>[];

  for (final k in keys) {
    final b = beforeMap[k];
    final a = afterMap[k];
    if (b == null && a != null) {
      out.add('新增：${_formatEvent(a)}');
    } else if (b != null && a == null) {
      out.add('删除：${_formatEvent(b)}');
    } else if (b != null && a != null) {
      final changed = _diffEvent(b, a);
      if (changed != null && changed.isNotEmpty) {
        out.add(changed);
      }
    }

    if (out.length >= maxLines) break;
  }

  return out;
}

void _putUnique(Map<String, EventItem> map, String key, EventItem e) {
  if (!map.containsKey(key)) {
    map[key] = e;
    return;
  }
  for (int i = 2; i < 1000; i++) {
    final k = '$key|#$i';
    if (!map.containsKey(k)) {
      map[k] = e;
      return;
    }
  }
}

String _eventKey(EventItem e) {
  final id = e.eventID;
  if (id != null && id.trim().isNotEmpty) {
    final dup = e.duplicateGroup?.toString() ?? '';
    final dupType = e.duplicateGroupType ?? '';
    return 'id:$id|d:$dupType:$dup';
  }

  final name = (e.eventName ?? '').trim();
  final teacher = (e.memberName ?? '').trim();
  final type = (e.eventType ?? '').trim();
  final cover = (e.weekCover ?? '').trim();
  final group = e.duplicateGroup?.toString() ?? '';
  final groupType = (e.duplicateGroupType ?? '').trim();
  return 'n:$name|t:$teacher|tp:$type|c:$cover|g:$groupType:$group';
}

String _formatEvent(EventItem e) {
  final name = (e.eventName ?? '未知课程').trim();
  final teacher = (e.memberName ?? '').trim();
  final address = (e.address ?? '').trim();
  final weekDay = _formatWeekday(e.weekDay);
  final time = _formatSessions(e);

  final segs = <String>[name];
  if (teacher.isNotEmpty) segs.add('（$teacher）');
  final main = segs.join();

  final tail = <String>[];
  if (weekDay.isNotEmpty) tail.add(weekDay);
  if (time.isNotEmpty) tail.add(time);
  if (address.isNotEmpty) tail.add(address);

  if (tail.isEmpty) return main;
  return '$main ${tail.join(' ')}';
}

String _formatWeekday(String? raw) {
  final s = (raw ?? '').trim();
  if (s.isEmpty) return '';
  final v = int.tryParse(s);
  if (v == null) {
    if (s.length == 1) return '周$s';
    if (s.startsWith('周')) return s;
    return s;
  }
  return '周${_toChineseWeekday(v)}';
}

String _toChineseWeekday(int mondayBased) {
  return switch (mondayBased) {
    1 => '一',
    2 => '二',
    3 => '三',
    4 => '四',
    5 => '五',
    6 => '六',
    7 => '日',
    _ => '一',
  };
}

String _formatSessions(EventItem e) {
  final start = (e.sessionStart ?? '').trim();
  final last = (e.sessionLast ?? '').trim();
  if (start.isNotEmpty && last.isNotEmpty) {
    return '$start-$last节';
  }
  final list = e.sessionList ?? const <String>[];
  final cleaned = list.map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (cleaned.isEmpty) return '';
  if (cleaned.length == 1) return '${cleaned.first}节';
  return '${cleaned.first}-${cleaned.last}节';
}

String? _diffEvent(EventItem before, EventItem after) {
  final changes = <String>[];

  final beforeWeekDay = (before.weekDay ?? '').trim();
  final afterWeekDay = (after.weekDay ?? '').trim();
  final beforeTime = _formatSessions(before);
  final afterTime = _formatSessions(after);
  if (beforeWeekDay != afterWeekDay || beforeTime != afterTime) {
    final from = '${_formatWeekday(beforeWeekDay)} $beforeTime'.trim();
    final to = '${_formatWeekday(afterWeekDay)} $afterTime'.trim();
    if (from.isNotEmpty || to.isNotEmpty) {
      changes.add('时间 $from → $to');
    }
  }

  final beforeAddr = (before.address ?? '').trim();
  final afterAddr = (after.address ?? '').trim();
  if (beforeAddr != afterAddr) {
    changes.add(
      '地点 ${beforeAddr.isEmpty ? '-' : beforeAddr} → ${afterAddr.isEmpty ? '-' : afterAddr}',
    );
  }

  final beforeTeacher = (before.memberName ?? '').trim();
  final afterTeacher = (after.memberName ?? '').trim();
  if (beforeTeacher != afterTeacher &&
      (beforeTeacher.isNotEmpty || afterTeacher.isNotEmpty)) {
    changes.add(
      '教师 ${beforeTeacher.isEmpty ? '-' : beforeTeacher} → ${afterTeacher.isEmpty ? '-' : afterTeacher}',
    );
  }

  final beforeName = (before.eventName ?? '').trim();
  final afterName = (after.eventName ?? '').trim();
  if (beforeName != afterName &&
      (beforeName.isNotEmpty || afterName.isNotEmpty)) {
    changes.add(
      '课程 ${beforeName.isEmpty ? '-' : beforeName} → ${afterName.isEmpty ? '-' : afterName}',
    );
  }

  if (changes.isEmpty) return null;

  final title = (after.eventName ?? before.eventName ?? '课程').trim();
  return '$title：${changes.join('；')}';
}
