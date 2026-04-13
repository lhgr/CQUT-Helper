import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';

String scheduleFingerprintFromWeekJsonMap(Map<String, dynamic> jsonMap) {
  final eventsRaw = jsonMap['eventList'];
  if (eventsRaw is! List) {
    return sha256.convert(utf8.encode('no_events')).toString();
  }

  final sigs = <String>[];
  for (final it in eventsRaw) {
    if (it is! Map) continue;
    final m = it.cast<String, dynamic>();

    String norm(dynamic v) => (v ?? '').toString().trim();
    String normInt(dynamic v) => v == null ? '' : v.toString().trim();
    String normList(dynamic v) {
      if (v is! List) return '';
      return v.map((e) => (e ?? '').toString().trim()).join(',');
    }

    final eventId = norm(m['eventID']);
    final eventName = norm(m['eventName']);
    final teacher = norm(m['memberName']);
    final address = norm(m['address']);
    final weekDay = norm(m['weekDay']);
    final weekNum = norm(m['weekNum']);
    final weekCover = norm(m['weekCover']);
    final weekList = normList(m['weekList']);
    final sessionList = normList(m['sessionList']);
    final sessionStart = normInt(m['sessionStart']);
    final sessionLast = normInt(m['sessionLast']);
    final dupType = norm(m['duplicateGroupType']);
    final dupGroup = normInt(m['duplicateGroup']);
    final eventType = norm(m['eventType']);

    final key = eventId.isNotEmpty
        ? 'id=$eventId'
        : 'k=$eventName|$teacher|$address|$weekDay|$sessionStart|$sessionLast|$sessionList|$weekList|$weekCover|$dupType|$dupGroup|$eventType';

    sigs.add(
      [
        key,
        'n=$eventName',
        't=$teacher',
        'a=$address',
        'd=$weekDay',
        'w=$weekNum',
        's=$sessionStart',
        'l=$sessionLast',
        'sl=$sessionList',
        'wl=$weekList',
        'wc=$weekCover',
        'dt=$dupType',
        'dg=$dupGroup',
        'et=$eventType',
      ].join(';'),
    );
  }

  sigs.sort();
  final canonical = json.encode(sigs);
  return sha256.convert(utf8.encode(canonical)).toString();
}

String scheduleFingerprintFromScheduleData(ScheduleData data) {
  final events = data.eventList;
  if (events == null || events.isEmpty) {
    return sha256.convert(utf8.encode('no_events')).toString();
  }

  String norm(String? v) => (v ?? '').toString().trim();
  String normInt(Object? v) => v == null ? '' : v.toString().trim();
  String normList(List<String>? v) {
    if (v == null || v.isEmpty) return '';
    return v.map((e) => (e).toString().trim()).join(',');
  }

  final sigs = <String>[];
  for (final e in events) {
    final eventId = norm(e.eventID);
    final eventName = norm(e.eventName);
    final teacher = norm(e.memberName);
    final address = norm(e.address);
    final weekDay = norm(e.weekDay);
    final weekNum = norm(e.weekNum);
    final weekCover = norm(e.weekCover);
    final weekList = normList(e.weekList);
    final sessionList = normList(e.sessionList);
    final sessionStart = normInt(e.sessionStart);
    final sessionLast = normInt(e.sessionLast);
    final dupType = norm(e.duplicateGroupType);
    final dupGroup = normInt(e.duplicateGroup);
    final eventType = norm(e.eventType);

    final key = eventId.isNotEmpty
        ? 'id=$eventId'
        : 'k=$eventName|$teacher|$address|$weekDay|$sessionStart|$sessionLast|$sessionList|$weekList|$weekCover|$dupType|$dupGroup|$eventType';

    sigs.add(
      [
        key,
        'n=$eventName',
        't=$teacher',
        'a=$address',
        'd=$weekDay',
        'w=$weekNum',
        's=$sessionStart',
        'l=$sessionLast',
        'sl=$sessionList',
        'wl=$weekList',
        'wc=$weekCover',
        'dt=$dupType',
        'dg=$dupGroup',
        'et=$eventType',
      ].join(';'),
    );
  }

  sigs.sort();
  final canonical = json.encode(sigs);
  return sha256.convert(utf8.encode(canonical)).toString();
}

typedef ScheduleDeltaStats = ({
  int added,
  int removed,
  int changed,
  int same,
});

ScheduleDeltaStats diffWeekEventFingerprints({
  required Map<String, dynamic>? beforeJson,
  required Map<String, dynamic> afterJson,
}) {
  Map<String, String> index(Map<String, dynamic>? m) {
    final events = m?['eventList'];
    if (events is! List) return const <String, String>{};
    final out = <String, String>{};

    for (final it in events) {
      if (it is! Map) continue;
      final e = it.cast<String, dynamic>();
      String norm(dynamic v) => (v ?? '').toString().trim();
      String normList(dynamic v) {
        if (v is! List) return '';
        return v.map((x) => (x ?? '').toString().trim()).join(',');
      }

      final id = norm(e['eventID']);
      final key = id.isNotEmpty
          ? 'id=$id'
          : [
              norm(e['eventName']),
              norm(e['memberName']),
              norm(e['address']),
              norm(e['weekDay']),
              norm(e['sessionStart']),
              norm(e['sessionLast']),
              normList(e['sessionList']),
              normList(e['weekList']),
              norm(e['weekCover']),
              norm(e['duplicateGroupType']),
              norm(e['duplicateGroup']),
              norm(e['eventType']),
            ].join('|');

      final fp = sha256
          .convert(
            utf8.encode(
              [
                norm(e['eventName']),
                norm(e['memberName']),
                norm(e['address']),
                norm(e['weekDay']),
                norm(e['weekNum']),
                norm(e['sessionStart']),
                norm(e['sessionLast']),
                normList(e['sessionList']),
                normList(e['weekList']),
                norm(e['weekCover']),
                norm(e['duplicateGroupType']),
                norm(e['duplicateGroup']),
                norm(e['eventType']),
                norm(e['eventID']),
              ].join(';'),
            ),
          )
          .toString();
      out[key] = fp;
    }
    return out;
  }

  final before = index(beforeJson);
  final after = index(afterJson);

  int added = 0;
  int removed = 0;
  int changed = 0;
  int same = 0;

  for (final key in after.keys) {
    final b = before[key];
    if (b == null) {
      added++;
    } else if (b == after[key]) {
      same++;
    } else {
      changed++;
    }
  }
  for (final key in before.keys) {
    if (!after.containsKey(key)) removed++;
  }

  return (added: added, removed: removed, changed: changed, same: same);
}
