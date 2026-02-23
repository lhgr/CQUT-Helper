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
  bool _checkInFlight = false;

  ScheduleUpdateManager({required this.controller, required this.settings});

  void dispose() {
    stopTimer();
  }

  void startTimer(
    ScheduleData? Function() currentDataGetter,
    Function(List<ScheduleWeekChange>) onChangesFound,
  ) {
    stopTimer();
    if (!settings.updateEnabled || settings.updateIntervalMinutes < 1) return;

    _timer = Timer.periodic(
      Duration(minutes: settings.updateIntervalMinutes),
      (_) async {
        final currentData = currentDataGetter();
        if (currentData == null) return;
        final changes = await checkForUpdates(currentData);
        if (changes.isNotEmpty) {
          onChangesFound(changes);
        }
      },
    );
  }

  void stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  Future<List<ScheduleWeekChange>> checkForUpdates(
    ScheduleData currentData,
  ) async {
    if (_checkInFlight) return [];
    _checkInFlight = true;
    try {
      final startAt = DateTime.now();
      final maxWeeksAhead = maxWeeksAheadForSchedule(
        weekList: currentData.weekList,
        currentWeek: currentData.weekNum,
      );
      final weeksAhead = settings.updateWeeksAhead.clamp(0, maxWeeksAhead);
      final changes = await controller.silentCheckRecentWeeksForChangesDetailed(
        currentData,
        weeksAhead: weeksAhead,
      );
      if (changes.isNotEmpty) {
        ScheduleUpdateIntents.requestScheduleUpdated();
      }

      final durationMs = DateTime.now().difference(startAt).inMilliseconds;
      await ScheduleUpdateLog.appendRun({
        'at': DateTime.now().millisecondsSinceEpoch,
        'type': 'foreground_timer',
        'weeksPlanned': 1 + weeksAhead,
        'weeksChanged': changes.length,
        'durationMs': durationMs,
      });

      return changes;
    } finally {
      _checkInFlight = false;
    }
  }

  Future<List<ScheduleWeekChange>> checkPendingChanges() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('account');
    if (userId == null || userId.trim().isEmpty) return [];

    final key = ScheduleUpdateWorker.pendingKeyForUser(userId);
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return [];
    await prefs.remove(key);

    try {
      final decoded = json.decode(raw);
      if (decoded is! Map<String, dynamic>) return [];
      final items = decoded['changes'];
      if (items is! List) return [];

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
      return changes;
    } catch (_) {
      return [];
    }
  }
}
