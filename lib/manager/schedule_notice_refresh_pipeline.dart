import 'dart:convert';

import 'package:cqut_helper/api/notice/notice_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
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
  final String? skipReason;

  const ScheduleNoticeRefreshResult({
    required this.changes,
    required this.changedNoticeCount,
    required this.affectedWeeks,
    required this.affectedKeys,
    required this.apiClosed,
    required this.generatedAt,
    this.skipReason,
  });
}

class ScheduleNoticeRefreshPipeline {
  final ScheduleApi scheduleApi;
  final CredentialStore credentialStore;
  final Future<void> Function(String weekNum, String yearTerm) refreshWeek;
  final Future<SharedPreferences> Function() prefsProvider;
  final DateTime Function() nowProvider;
  String _stage = 'not_started';
  final List<String> _completedStages = [];
  int _refreshedWeekCount = 0;

  /// Only phase names and counts: no notice text, credentials, or week data.
  /// The caller attaches this bounded snapshot if the pipeline fails.
  Map<String, Object?> get diagnosticProgress => {
    'pipeline_stage': _stage,
    'pipeline_completed_stages': List<String>.of(_completedStages),
    'refreshed_week_count': _refreshedWeekCount,
  };

  ScheduleNoticeRefreshResult _skip(String reason, {bool apiClosed = false}) {
    _stage = 'skipped';
    return ScheduleNoticeRefreshResult(
      changes: const <ScheduleWeekChange>[],
      changedNoticeCount: 0,
      affectedWeeks: const <String>{},
      affectedKeys: const <String>{},
      apiClosed: apiClosed,
      generatedAt: '',
      skipReason: reason,
    );
  }

  ScheduleNoticeRefreshPipeline({
    required this.refreshWeek,
    ScheduleApi? scheduleApi,
    CredentialStore? credentialStore,
    Future<SharedPreferences> Function()? prefsProvider,
    DateTime Function()? nowProvider,
  }) : scheduleApi = scheduleApi ?? ScheduleApi(),
       credentialStore = credentialStore ?? CredentialStore(),
       prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
       nowProvider = nowProvider ?? DateTime.now;

  String _stateKey(String userId, String yearTerm) =>
      'schedule_notice_state_${userId}_$yearTerm';

  String _loginMarkerKey(String userId) =>
      'schedule_notice_login_marker_$userId';

  Future<ScheduleNoticeRefreshResult> run({
    required ScheduleData currentData,
    String envName = 'prod',
    bool headless = true,
  }) async {
    _stage = 'validate_schedule';
    _completedStages.clear();
    _refreshedWeekCount = 0;
    final now = nowProvider();
    final nowHour = now.hour;
    if (nowHour >= 0 && nowHour < 7) {
      return _skip('deep_night', apiClosed: true);
    }
    final yearTerm = (currentData.yearTerm ?? '').trim();
    final weekList = currentData.weekList ?? const <String>[];
    if (yearTerm.isEmpty || weekList.isEmpty) {
      return _skip('invalid_schedule_data');
    }
    if (!RegExp(r'^\d{4}-\d{4}-[12]$').hasMatch(yearTerm)) {
      throw ArgumentError.value(yearTerm, 'yearTerm', '学期格式错误，应为YYYY-YYYY-1/2');
    }

    _completedStages.add(_stage);
    _stage = 'validate_credentials';
    final prefs = await prefsProvider();
    if (!ScheduleSettingsManager.isNoticeEnhancementEnabledIn(prefs)) {
      return _skip('disabled');
    }
    final userId = (prefs.getString('account') ?? '').trim();
    final encryptedPassword =
        ((await credentialStore.readEncryptedPassword()) ?? '').trim();
    if (userId.isEmpty || encryptedPassword.isEmpty) {
      return _skip('missing_credentials');
    }

    _completedStages.add(_stage);
    _stage = 'fetch_notices';
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
      return _skip('api_closed', apiClosed: true);
    }
    _completedStages.add(_stage);
    _stage = 'compare_notices';
    final polledYearTerm = pollData.yearTerm.trim();
    if (polledYearTerm.isNotEmpty && polledYearTerm != yearTerm) {
      throw StateError(
        '调课通知轮询学期不一致: current=$yearTerm, polled=$polledYearTerm',
      );
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
      _completedStages.add(_stage);
      _stage = 'write_notice_state';
      final initialState = <String, dynamic>{
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'generatedAt': pollData.generatedAt,
        'loginMarker': loginMarker,
        'notices': currentNotices,
      };
      await prefs.setString(stateKey, json.encode(initialState));
      _completedStages.add(_stage);
      _stage = 'completed';
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

    _completedStages.add(_stage);
    _stage = 'refresh_affected_weeks';
    for (final week in affectedWeeks) {
      await refreshWeek(week, yearTerm);
      _refreshedWeekCount++;
    }
    _completedStages.add(_stage);

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

    _stage = 'write_notice_state';
    final newState = <String, dynamic>{
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
      'generatedAt': pollData.generatedAt,
      'loginMarker': loginMarker,
      'notices': currentNotices,
    };
    await prefs.setString(stateKey, json.encode(newState));
    _completedStages.add(_stage);
    _stage = 'completed';

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
