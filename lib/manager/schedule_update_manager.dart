import 'dart:async';
import 'dart:convert';
import 'package:cqut/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/model/schedule_week_change.dart';
import 'package:cqut/manager/schedule_update_worker.dart';
import 'package:cqut/manager/schedule_update_intents.dart';
import 'package:cqut/utils/schedule_update_range_utils.dart';
import 'package:cqut/utils/schedule_update_log.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'schedule_settings_manager.dart';

class ScheduleUpdateManager {
  final ScheduleController controller;
  final ScheduleSettingsManager settings;
  Timer? _timer;
  Timer? _retryTimer;
  bool _checkInFlight = false;
  int _retryBackoffMinutes = 0;
  ScheduleData? Function()? _currentDataGetter;
  Function(List<ScheduleWeekChange>)? _onChangesFound;

  ScheduleUpdateManager({required this.controller, required this.settings});

  void dispose() {
    stopTimer();
  }

  void startTimer(
    ScheduleData? Function() currentDataGetter,
    Function(List<ScheduleWeekChange>) onChangesFound,
  ) {
    stopTimer();
    _currentDataGetter = currentDataGetter;
    _onChangesFound = onChangesFound;
    if (!settings.updateEnabled || settings.updateIntervalMinutes < 1) return;

    _timer = Timer.periodic(Duration(minutes: settings.updateIntervalMinutes), (
      _,
    ) async {
      final currentData = currentDataGetter();
      if (currentData == null) return;
      final result = await _checkForUpdatesInternal(
        currentData,
        runType: 'foreground_timer',
      );
      final changes = result.changes;
      if (changes.isNotEmpty) {
        onChangesFound(changes);
      }
      _handleRetryAfterRun(result.hadFailures, currentData);
    });
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    _retryBackoffMinutes = 0;
    _currentDataGetter = null;
    _onChangesFound = null;
  }

  Future<List<ScheduleWeekChange>> checkForUpdates(
    ScheduleData currentData,
  ) async {
    final result = await _checkForUpdatesInternal(
      currentData,
      runType: 'foreground_manual',
    );
    return result.changes;
  }

  Future<
    ({List<ScheduleWeekChange> changes, bool hadFailures, int failureDelta})
  >
  _checkForUpdatesInternal(
    ScheduleData currentData, {
    required String runType,
  }) async {
    if (_checkInFlight) {
      return (
        changes: const <ScheduleWeekChange>[],
        hadFailures: false,
        failureDelta: 0,
      );
    }
    _checkInFlight = true;
    final startAt = DateTime.now();
    final failuresBefore = await ScheduleUpdateLog.failureCounter();
    List<ScheduleWeekChange> changes = const <ScheduleWeekChange>[];
    Object? error;
    StackTrace? stackTrace;
    int weeksAhead = 0;
    int weeksPlanned = 1;
    int failureDelta = 0;
    bool hadFailures = false;
    try {
      final maxWeeksAhead = maxWeeksAheadForSchedule(
        weekList: currentData.weekList,
        currentWeek: currentData.weekNum,
      );
      weeksAhead = settings.updateWeeksAhead.clamp(0, maxWeeksAhead);
      weeksPlanned = 1 + weeksAhead;
      changes = await controller.silentCheckRecentWeeksForChangesDetailed(
        currentData,
        weeksAhead: weeksAhead,
      );
      if (changes.isNotEmpty) {
        ScheduleUpdateIntents.requestScheduleUpdated();
      }
    } catch (e, st) {
      error = e;
      stackTrace = st;
      await ScheduleUpdateLog.appendFailure({
        'at': DateTime.now().millisecondsSinceEpoch,
        'scope': runType,
        'error': e.toString(),
      });
    } finally {
      final failuresAfter = await ScheduleUpdateLog.failureCounter();
      failureDelta = failuresAfter - failuresBefore;
      hadFailures = error != null || failureDelta > 0;
      final durationMs = DateTime.now().difference(startAt).inMilliseconds;
      await ScheduleUpdateLog.appendRun({
        'at': DateTime.now().millisecondsSinceEpoch,
        'type': runType,
        'weeksPlanned': weeksPlanned,
        'weeksChanged': changes.length,
        'durationMs': durationMs,
        'hadFailures': hadFailures,
        'failureDelta': failureDelta,
      });
      if (stackTrace != null) {
        await ScheduleUpdateLog.appendRun({
          'at': DateTime.now().millisecondsSinceEpoch,
          'type': '${runType}_exception',
          'error': error.toString(),
          'stack': stackTrace.toString(),
        });
      }
      _checkInFlight = false;
    }
    return (
      changes: changes,
      hadFailures: hadFailures,
      failureDelta: failureDelta,
    );
  }

  void _handleRetryAfterRun(bool hadFailures, ScheduleData currentData) {
    if (!hadFailures) {
      _retryBackoffMinutes = 0;
      _retryTimer?.cancel();
      _retryTimer = null;
      return;
    }
    if (!settings.updateEnabled || settings.updateIntervalMinutes < 1) return;
    if (_retryTimer != null) return;
    final base = settings.updateIntervalMinutes;
    final next = _retryBackoffMinutes <= 0 ? 5 : (_retryBackoffMinutes * 2);
    _retryBackoffMinutes = next > base ? base : next;
    _retryTimer = Timer(Duration(minutes: _retryBackoffMinutes), () async {
      _retryTimer = null;
      final getter = _currentDataGetter;
      final onChangesFound = _onChangesFound;
      if (getter == null || onChangesFound == null) return;
      final fresh = getter();
      if (fresh == null) return;
      final result = await _checkForUpdatesInternal(
        fresh,
        runType: 'foreground_retry',
      );
      if (result.changes.isNotEmpty) {
        onChangesFound(result.changes);
      }
      _handleRetryAfterRun(result.hadFailures, fresh);
    });
  }

  Future<({String? yearTerm, List<ScheduleWeekChange> changes})>
  checkPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('account');
    if (userId == null || userId.trim().isEmpty) {
      return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
    }

    final key = ScheduleUpdateWorker.pendingKeyForUser(userId);
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) {
      return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
    }
    await prefs.remove(key);

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) {
        return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
      }
      final yearTerm = (decoded['yearTerm'] ?? '').toString().trim();
      final items = decoded['changes'];
      if (items is! List) {
        return (
          yearTerm: yearTerm.isEmpty ? null : yearTerm,
          changes: const <ScheduleWeekChange>[],
        );
      }

      final changes = <ScheduleWeekChange>[];
      for (final it in items) {
        if (it is! Map) continue;
        final weekNum = (it['weekNum'] ?? '').toString();
        final linesRaw = it['lines'];
        final lines = linesRaw is List
            ? linesRaw.map((e) => e.toString()).toList()
            : const <String>[];
        if (weekNum.isEmpty) continue;
        changes.add(ScheduleWeekChange(weekNum: weekNum, lines: lines));
      }
      return (yearTerm: yearTerm.isEmpty ? null : yearTerm, changes: changes);
    } catch (_) {
      return (yearTerm: null, changes: const <ScheduleWeekChange>[]);
    }
  }
}
