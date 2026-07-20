import 'dart:convert';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_week_loader.dart';
import 'package:cqut_helper/utils/retry_utils.dart';
import 'package:cqut_helper/utils/schedule_diff_utils.dart';
import 'package:cqut_helper/utils/schedule_fingerprint_utils.dart';
import 'package:cqut_helper/utils/schedule_update_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleRecentChangeDetector {
  final ScheduleApi service;
  final ScheduleWeekLoader weekLoader;
  final Map<int, ScheduleData> Function() getWeekCache;
  final bool Function() isDisposed;

  ScheduleRecentChangeDetector({
    required this.service,
    required this.weekLoader,
    required this.getWeekCache,
    required this.isDisposed,
  });

  String _notifiedKey(String userId, String yearTerm, String weekNum) =>
      'schedule_notified_fp_${userId}_${yearTerm}_$weekNum';

  String _stableEventKey(EventItem event) {
    final id = (event.eventID ?? '').trim();
    if (id.isNotEmpty) {
      final dup = event.duplicateGroup?.toString() ?? '';
      final dupType = (event.duplicateGroupType ?? '').trim();
      return 'id:$id|d:$dupType:$dup';
    }
    final name = (event.eventName ?? '').trim();
    final teacher = (event.memberName ?? '').trim();
    final type = (event.eventType ?? '').trim();
    final cover = (event.weekCover ?? '').trim();
    final group = event.duplicateGroup?.toString() ?? '';
    final groupType = (event.duplicateGroupType ?? '').trim();
    return 'n:$name|t:$teacher|tp:$type|c:$cover|g:$groupType:$group';
  }

  Set<String> _stableKeysFromEvents(List<EventItem>? list) {
    if (list == null || list.isEmpty) return <String>{};
    return list.map(_stableEventKey).where((key) => key.isNotEmpty).toSet();
  }

  Future<List<ScheduleWeekChange>> silentCheckRecentWeeksForChangesDetailed(
    ScheduleData currentData, {
    int weeksAhead = 1,
    int maxDiffLinesPerWeek = 30,
  }) async {
    final wList = currentData.weekList;
    final currentWeekStr = currentData.weekNum;
    final cTerm = currentData.yearTerm;
    if (wList == null || currentWeekStr == null || cTerm == null) return [];

    final currentIndex = wList.indexOf(currentWeekStr);
    if (currentIndex == -1) return [];

    await weekLoader.loadCredentials();
    final userId = weekLoader.userId;
    final encryptedPassword = weekLoader.encryptedPassword;
    if (userId == null || userId.isEmpty) return [];
    if (encryptedPassword == null || encryptedPassword.isEmpty) return [];

    final prefs = await SharedPreferences.getInstance();
    final changed = <ScheduleWeekChange>[];
    final removedStableKeys = <String>{};
    var forceScanRemaining = false;

    final candidates = <String>[currentWeekStr];
    for (int offset = 1; offset <= weeksAhead; offset++) {
      final idx = currentIndex + offset;
      if (idx < 0 || idx >= wList.length) continue;
      candidates.add(wList[idx]);
    }

    for (final week in candidates) {
      if (isDisposed()) break;

      final beforeJsonStr = await service.getCachedScheduleJson(
        userId: userId,
        yearTerm: cTerm,
        weekNum: week,
      );

      final fpKey = weekLoader.fingerprintKey(userId, cTerm, week);
      final fpUpdatedAtKey = weekLoader.fingerprintUpdatedAtKey(userId, cTerm, week);
      final fetchAtKey = weekLoader.lastFetchAtKey(userId, cTerm, week);

      final lastFetchAt = prefs.getInt(fetchAtKey) ?? 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (!forceScanRemaining &&
          lastFetchAt > 0 &&
          nowMs - lastFetchAt < 5 * 60 * 1000) {
        continue;
      }

      Map<String, dynamic>? beforeJson;
      String? beforeFp = prefs.getString(fpKey);
      if (beforeFp == null && beforeJsonStr != null && beforeJsonStr.isNotEmpty) {
        try {
          final decoded = json.decode(beforeJsonStr);
          if (decoded is Map<String, dynamic>) {
            beforeJson = decoded;
            beforeFp = scheduleFingerprintFromWeekJsonMap(decoded);
            await prefs.setString(fpKey, beforeFp);
            await prefs.setInt(
              fpUpdatedAtKey,
              DateTime.now().millisecondsSinceEpoch,
            );
          }
        } catch (_) {}
      }

      Map<String, dynamic>? afterJson;
      Object? lastError;
      var lastAttempt = 0;
      try {
        afterJson = await retryWithExponentialBackoff<Map<String, dynamic>>(
          () => service.fetchRawWeekEvents(
            userId: userId,
            encryptedPassword: encryptedPassword,
            weekNum: week,
            yearTerm: cTerm,
          ),
          maxAttempts: 3,
          onError: (attempt, error) {
            lastAttempt = attempt;
            lastError = error;
          },
        );
      } catch (_) {
        await ScheduleUpdateLog.appendFailure({
          'at': DateTime.now().millisecondsSinceEpoch,
          'scope': 'silent_check',
          'userId': userId,
          'yearTerm': cTerm,
          'weekNum': week,
          'attempt': lastAttempt,
          'error': (lastError ?? 'unknown').toString(),
        });
        continue;
      }

      final afterFp = scheduleFingerprintFromWeekJsonMap(afterJson);
      await prefs.setInt(fetchAtKey, DateTime.now().millisecondsSinceEpoch);
      if (beforeFp != null && beforeFp == afterFp) continue;
      if (beforeFp != null && beforeFp != afterFp) {
        forceScanRemaining = true;
      }

      final afterData = ScheduleData.fromJson(afterJson);
      if (afterData.weekNum != null && afterData.yearTerm != null) {
        final afterStr = json.encode(afterJson);
        await service.saveScheduleJson(
          userId: userId,
          yearTerm: cTerm,
          weekNum: week,
          jsonStr: afterStr,
        );
        await prefs.setString(fpKey, afterFp);
        await prefs.setInt(fpUpdatedAtKey, DateTime.now().millisecondsSinceEpoch);

        final wInt = int.tryParse(afterData.weekNum!) ?? 0;
        getWeekCache()[wInt] = afterData;

        if (beforeJson != null) {
          final stats = diffWeekEventFingerprints(
            beforeJson: beforeJson,
            afterJson: afterJson,
          );
          await ScheduleUpdateLog.appendRun({
            'at': DateTime.now().millisecondsSinceEpoch,
            'type': 'week_update',
            'userId': userId,
            'yearTerm': cTerm,
            'weekNum': week,
            'bytes': afterStr.length,
            'delta': {
              'added': stats.added,
              'removed': stats.removed,
              'changed': stats.changed,
              'same': stats.same,
            },
          });
        }
      }

      if (beforeFp == null) {
        final movedAdded = (afterData.eventList ?? const <EventItem>[])
            .where((event) => removedStableKeys.contains(_stableEventKey(event)))
            .toList(growable: false);
        if (movedAdded.isNotEmpty) {
          final beforeEmpty = ScheduleData(
            weekNum: week,
            eventList: const <EventItem>[],
          );
          final afterOnlyMoved = ScheduleData(weekNum: week, eventList: movedAdded);
          final lines = diffScheduleWeekLines(
            before: beforeEmpty,
            after: afterOnlyMoved,
            maxLines: maxDiffLinesPerWeek,
          );
          if (lines.isNotEmpty) {
            changed.add(ScheduleWeekChange(weekNum: week, lines: lines));
          }
        }
        continue;
      }

      final notifiedKey = _notifiedKey(userId, cTerm, week);
      final lastNotifiedFp = prefs.getString(notifiedKey);
      if (lastNotifiedFp == afterFp) continue;

      List<String> lines = const <String>[];
      try {
        if (beforeJson == null && beforeJsonStr != null && beforeJsonStr.isNotEmpty) {
          final decoded = json.decode(beforeJsonStr);
          if (decoded is Map<String, dynamic>) beforeJson = decoded;
        }

        ScheduleData? beforeData;
        if (beforeJson != null) {
          beforeData = ScheduleData.fromJson(beforeJson);
        } else {
          final wInt = int.tryParse(week) ?? 0;
          beforeData = getWeekCache()[wInt];
        }

        if (beforeData != null) {
          final beforeKeys = _stableKeysFromEvents(beforeData.eventList);
          final afterKeys = _stableKeysFromEvents(afterData.eventList);
          if (beforeKeys.isNotEmpty) {
            removedStableKeys.addAll(beforeKeys.difference(afterKeys));
          }
          lines = diffScheduleWeekLines(
            before: beforeData,
            after: afterData,
            maxLines: maxDiffLinesPerWeek,
          );
        }

        if (lines.isEmpty && beforeJson != null) {
          final stats = diffWeekEventFingerprints(
            beforeJson: beforeJson,
            afterJson: afterJson,
          );
          if (stats.added > 0 || stats.removed > 0 || stats.changed > 0) {
            lines = [
              '变更概览：新增${stats.added} 删除${stats.removed} 修改${stats.changed}',
            ];
          }
        }
      } catch (_) {}

      await prefs.setString(notifiedKey, afterFp);
      changed.add(ScheduleWeekChange(weekNum: week, lines: lines));
    }

    return changed;
  }
}
