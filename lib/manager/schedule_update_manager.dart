import 'dart:async';
import 'dart:convert';
import 'package:cqut/pages/ClassSchedule/controllers/schedule_controller.dart';
import 'package:cqut/model/class_schedule_model.dart';
import 'package:cqut/model/schedule_week_change.dart';
import 'package:cqut/manager/schedule_update_worker.dart';
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
      final maxWeeksAhead = _maxWeeksAheadForCurrentTerm(currentData);
      final weeksAhead = settings.updateWeeksAhead.clamp(0, maxWeeksAhead);
      return await controller.silentCheckRecentWeeksForChangesDetailed(
        currentData,
        weeksAhead: weeksAhead,
      );
    } finally {
      _checkInFlight = false;
    }
  }

  int _maxWeeksAheadForCurrentTerm(ScheduleData currentData) {
    final totalWeeks = currentData.weekList?.length ?? 0;
    if (totalWeeks <= 1) return 0;
    return totalWeeks - 1;
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
