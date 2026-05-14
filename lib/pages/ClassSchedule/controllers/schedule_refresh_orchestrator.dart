import 'dart:async';

import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ScheduleRefreshOrchestrator {
  final bool Function() isDisposed;
  final Future<void> Function(
    String weekNum,
    String yearTerm, {
    bool forceRefresh,
    bool updateLastViewed,
  }) ensureWeekLoaded;
  final Future<String?> Function() loadUserId;
  Timer? _prefetchTimer;
  Future<void>? _foregroundFullRefreshInFlight;

  ScheduleRefreshOrchestrator({
    required this.isDisposed,
    required this.ensureWeekLoaded,
    required this.loadUserId,
  });

  static const int _foregroundFullRefreshCooldownMs = 6 * 60 * 60 * 1000;

  void dispose() {
    _prefetchTimer?.cancel();
  }

  void cancelPrefetch() {
    _prefetchTimer?.cancel();
  }

  String _foregroundFullRefreshAtKey(String userId, String yearTerm) =>
      'schedule_foreground_full_refresh_at_${userId}_$yearTerm';

  void schedulePrefetch(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _prefetchTimer?.cancel();
    _prefetchTimer = Timer(delay, () {
      _prefetchAdjacentWeeks(currentData, onUpdate);
    });
  }

  Future<void> _prefetchAdjacentWeeks(
    ScheduleData currentData,
    Function() onUpdate,
  ) async {
    final wList = currentData.weekList;
    final currentWeekStr = currentData.weekNum;
    final cTerm = currentData.yearTerm;

    if (wList == null || currentWeekStr == null || cTerm == null) return;

    final currentIndex = wList.indexOf(currentWeekStr);
    if (currentIndex == -1) return;
    if (isDisposed()) return;

    final futures = <Future<void>>[];
    if (currentIndex > 0) {
      final prevWeek = wList[currentIndex - 1];
      futures.add(ensureWeekLoaded(prevWeek, cTerm));
    }
    if (currentIndex < wList.length - 1) {
      final nextWeek = wList[currentIndex + 1];
      futures.add(ensureWeekLoaded(nextWeek, cTerm));
    }

    if (futures.isEmpty) return;
    await Future.wait(futures);
    onUpdate();
  }

  void prefetchAllWeeksInBackground(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration interval = const Duration(milliseconds: 150),
    bool forceRefresh = false,
  }) {
    Future(() async {
      final wList = currentData.weekList;
      final currentWeekStr = currentData.weekNum;
      final cTerm = currentData.yearTerm;
      if (wList == null || currentWeekStr == null || cTerm == null) return;

      for (final week in wList) {
        if (isDisposed()) return;
        if (week == currentWeekStr) continue;
        await ensureWeekLoaded(week, cTerm, forceRefresh: forceRefresh);
        if (isDisposed()) return;
        onUpdate();
        if (interval > Duration.zero) {
          await Future.delayed(interval);
        }
      }
    });
  }

  Future<void> refreshAllWeeksInForeground(
    ScheduleData currentData, {
    Duration interval = const Duration(seconds: 2),
  }) async {
    if (isDisposed()) return;
    final inFlight = _foregroundFullRefreshInFlight;
    if (inFlight != null) return await inFlight;

    final future = _refreshAllWeeksInForegroundInternal(
      currentData,
      interval: interval,
    );
    _foregroundFullRefreshInFlight = future;
    try {
      await future;
    } finally {
      if (identical(_foregroundFullRefreshInFlight, future)) {
        _foregroundFullRefreshInFlight = null;
      }
    }
  }

  Future<void> _refreshAllWeeksInForegroundInternal(
    ScheduleData currentData, {
    required Duration interval,
  }) async {
    final wList = currentData.weekList;
    final term = (currentData.yearTerm ?? '').trim();
    if (wList == null || wList.isEmpty || term.isEmpty) return;

    final uid = (await loadUserId() ?? '').trim();
    if (uid.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final key = _foregroundFullRefreshAtKey(uid, term);
    final last = prefs.getInt(key) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (last > 0 && now - last < _foregroundFullRefreshCooldownMs) return;

    for (final week in wList) {
      if (isDisposed()) return;
      final w = week.trim();
      if (w.isEmpty) continue;
      await ensureWeekLoaded(
        w,
        term,
        forceRefresh: true,
        updateLastViewed: false,
      );
      if (isDisposed()) return;
      if (interval > Duration.zero) {
        await Future.delayed(interval);
      }
    }
    await prefs.setInt(key, DateTime.now().millisecondsSinceEpoch);
  }
}
