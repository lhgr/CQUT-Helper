import 'dart:convert';
import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_notice.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/utils/schedule_notice_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleNoticeRefreshResult {
  final List<ScheduleWeekChange> changes;
  final int changedNoticeCount;
  final Set<String> affectedWeeks;
  final Set<String> affectedKeys;
  final bool apiClosed;
  final String generatedAt;

  const ScheduleNoticeRefreshResult({
    required this.changes,
    required this.changedNoticeCount,
    required this.affectedWeeks,
    required this.affectedKeys,
    required this.apiClosed,
    required this.generatedAt,
  });
}

class ScheduleNoticeRefreshPipeline {
  final ScheduleApi scheduleApi;
  final Future<void> Function(String weekNum, String yearTerm) refreshWeek;
  final Future<SharedPreferences> Function() prefsProvider;
  final DateTime Function() nowProvider;

  ScheduleNoticeRefreshPipeline({
    required this.refreshWeek,
    ScheduleApi? scheduleApi,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime Function()? nowProvider,
  }) : scheduleApi = scheduleApi ?? ScheduleApi(),
       prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
       nowProvider = nowProvider ?? DateTime.now;

  String _stateKey(String userId, String yearTerm) =>
      'schedule_notice_state_${userId}_$yearTerm';

  String _loginMarkerKey(String userId) => 'schedule_notice_login_marker_$userId';

  Future<ScheduleNoticeRefreshResult> run({
    required ScheduleData currentData,
    String envName = 'prod',
    bool headless = true,
  }) async {
    final now = nowProvider();
    final nowHour = now.hour;
    if (nowHour >= 0 && nowHour < 7) {
      return const ScheduleNoticeRefreshResult(
        changes: <ScheduleWeekChange>[],
        changedNoticeCount: 0,
        affectedWeeks: <String>{},
        affectedKeys: <String>{},
        apiClosed: true,
        generatedAt: '',
      );
    }
    final yearTerm = (currentData.yearTerm ?? '').trim();
    final weekList = currentData.weekList ?? const <String>[];
    if (yearTerm.isEmpty || weekList.isEmpty) {
      return const ScheduleNoticeRefreshResult(
        changes: <ScheduleWeekChange>[],
        changedNoticeCount: 0,
        affectedWeeks: <String>{},
        affectedKeys: <String>{},
        apiClosed: false,
        generatedAt: '',
      );
    }
    if (!RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(yearTerm)) {
      throw ArgumentError.value(yearTerm, 'yearTerm', '学期格式错误，应为YYYY-YYYY-1/2');
    }

    final prefs = await prefsProvider();
    final userId = (prefs.getString('account') ?? '').trim();
    final encryptedPassword = (prefs.getString('encrypted_password') ?? '').trim();
    if (userId.isEmpty || encryptedPassword.isEmpty) {
      return const ScheduleNoticeRefreshResult(
        changes: <ScheduleWeekChange>[],
        changedNoticeCount: 0,
        affectedWeeks: <String>{},
        affectedKeys: <String>{},
        apiClosed: false,
        generatedAt: '',
      );
    }

    ScheduleNoticePollData pollData;
    try {
      pollData = await scheduleApi.fetchTermScheduleNotices(
        userId: userId,
        encryptedPassword: encryptedPassword,
        yearTerm: yearTerm,
        envName: envName,
        headless: headless,
      );
    } on NoticeApiForbiddenException {
      return const ScheduleNoticeRefreshResult(
        changes: <ScheduleWeekChange>[],
        changedNoticeCount: 0,
        affectedWeeks: <String>{},
        affectedKeys: <String>{},
        apiClosed: true,
        generatedAt: '',
      );
    }
    final polledYearTerm = pollData.yearTerm.trim();
    if (polledYearTerm.isNotEmpty && polledYearTerm != yearTerm) {
      throw StateError('调课通知轮询学期不一致: current=$yearTerm, polled=$polledYearTerm');
    }

    final stateKey = _stateKey(userId, yearTerm);
    final loginMarker = prefs.getInt(_loginMarkerKey(userId)) ?? 0;
    final previous = _loadState(prefs.getString(stateKey));
    final previousNotices = previous['notices'] as Map<String, dynamic>;
    final currentNotices = <String, Map<String, dynamic>>{};
    final changedImpacts = <ScheduleNoticeImpact>[];

    for (final notice in pollData.notices) {
      final impact = ScheduleNoticeParser.parseImpact(notice);
      currentNotices[impact.noticeId] = impact.toJson();
      final previousEntry = previousNotices[impact.noticeId];
      final previousVersion = previousEntry is Map
          ? (previousEntry['noticeVersion'] ?? '').toString().trim()
          : '';
      if (previousVersion != impact.noticeVersion) {
        changedImpacts.add(impact);
      }
    }

    final previousLoginMarker = (previous['loginMarker'] as num?)?.toInt() ?? 0;
    final isFirstSnapshot =
        previousNotices.isEmpty || previousLoginMarker != loginMarker;
    if (isFirstSnapshot) {
      final initialState = <String, dynamic>{
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'generatedAt': pollData.generatedAt,
        'loginMarker': loginMarker,
        'notices': currentNotices,
      };
      await prefs.setString(stateKey, json.encode(initialState));
      return ScheduleNoticeRefreshResult(
        changes: const <ScheduleWeekChange>[],
        changedNoticeCount: 0,
        affectedWeeks: const <String>{},
        affectedKeys: const <String>{},
        apiClosed: false,
        generatedAt: pollData.generatedAt,
      );
    }

    final removedIds = previousNotices.keys
        .where((id) => !currentNotices.containsKey(id))
        .toList(growable: false);
    for (final id in removedIds) {
      final raw = previousNotices[id];
      if (raw is! Map) continue;
      final parsed = ScheduleNoticeImpact.fromJson(raw.cast<String, dynamic>());
      changedImpacts.add(
        ScheduleNoticeImpact(
          noticeId: parsed.noticeId,
          noticeVersion: 'removed',
          weeks: parsed.weeks,
          keys: parsed.keys,
          line: '撤销调课通知',
        ),
      );
    }

    final availableWeeks = weekList.map((e) => e.trim()).toSet();
    final affectedWeeks = <String>{};
    final affectedKeys = <String>{};
    final weekLines = <String, List<String>>{};
    for (final impact in changedImpacts) {
      affectedKeys.addAll(impact.keys);
      for (final week in impact.weeks) {
        if (!availableWeeks.contains(week)) continue;
        affectedWeeks.add(week);
        weekLines.putIfAbsent(week, () => <String>[]);
        if (impact.line.isNotEmpty) {
          weekLines[week]!.add(impact.line);
        }
      }
    }

    for (final week in affectedWeeks) {
      await refreshWeek(week, yearTerm);
    }

    final changes = <ScheduleWeekChange>[];
    for (final week in affectedWeeks) {
      final lines = weekLines[week] ?? const <String>[];
      changes.add(ScheduleWeekChange(weekNum: week, lines: lines));
    }
    changes.sort((a, b) {
      final ai = int.tryParse(a.weekNum) ?? 0;
      final bi = int.tryParse(b.weekNum) ?? 0;
      return ai.compareTo(bi);
    });

    final newState = <String, dynamic>{
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'generatedAt': pollData.generatedAt,
      'loginMarker': loginMarker,
      'notices': currentNotices,
    };
    await prefs.setString(stateKey, json.encode(newState));

    return ScheduleNoticeRefreshResult(
      changes: changes,
      changedNoticeCount: changedImpacts.length,
      affectedWeeks: affectedWeeks,
      affectedKeys: affectedKeys,
      apiClosed: false,
      generatedAt: pollData.generatedAt,
    );
  }

  Map<String, dynamic> _loadState(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{'notices': <String, dynamic>{}};
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) {
        final notices = decoded['notices'];
        if (notices is Map<String, dynamic>) return decoded;
        if (notices is Map) {
          final copied = Map<String, dynamic>.from(decoded);
          copied['notices'] = notices.cast<String, dynamic>();
          return copied;
        }
      } else if (decoded is Map) {
        final casted = decoded.cast<String, dynamic>();
        final notices = casted['notices'];
        if (notices is Map) {
          return <String, dynamic>{
            ...casted,
            'notices': notices.cast<String, dynamic>(),
          };
        }
      }
    } catch (_) {}
    return <String, dynamic>{'notices': <String, dynamic>{}};
  }
}
