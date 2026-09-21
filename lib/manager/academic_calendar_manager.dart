import 'dart:async';
import 'dart:convert';

import 'package:cqut_helper/api/calendar/calendar_api.dart';
import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/course_reminder_scheduler.dart';
import 'package:cqut_helper/model/academic_calendar_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AcademicCalendarSyncPhase { idle, loading, success, unchanged, failure }

@immutable
class AcademicCalendarSyncState {
  const AcademicCalendarSyncState({
    required this.phase,
    this.errorMessage,
    this.changedDayCount = 0,
    this.lastSuccessfulAt,
    this.revision,
  });

  const AcademicCalendarSyncState.idle()
    : this(phase: AcademicCalendarSyncPhase.idle);

  final AcademicCalendarSyncPhase phase;
  final String? errorMessage;
  final int changedDayCount;
  final DateTime? lastSuccessfulAt;
  final String? revision;

  bool get isLoading => phase == AcademicCalendarSyncPhase.loading;
  bool get hasError => phase == AcademicCalendarSyncPhase.failure;
  String get message {
    switch (phase) {
      case AcademicCalendarSyncPhase.idle:
        return '尚未同步';
      case AcademicCalendarSyncPhase.loading:
        return '刷新中…';
      case AcademicCalendarSyncPhase.success:
        return changedDayCount > 0 ? '已更新 $changedDayCount 天' : '已更新';
      case AcademicCalendarSyncPhase.unchanged:
        return '已是最新';
      case AcademicCalendarSyncPhase.failure:
        return errorMessage ?? '校历刷新失败';
    }
  }
}

class AcademicCalendarSyncResult {
  const AcademicCalendarSyncResult({
    required this.updated,
    required this.notModified,
    this.snapshot,
    this.error,
  });

  final bool updated;
  final bool notModified;
  final AcademicCalendarSnapshot? snapshot;
  final Object? error;

  bool get succeeded => error == null;
}

/// Owns the published calendar cache and the intentionally explicit refresh
/// entry point used by settings. Calls for one term are coalesced.
class AcademicCalendarManager extends ChangeNotifier {
  AcademicCalendarManager({CalendarApi? api, ScheduleApi? scheduleApi})
    : _api = api ?? CalendarApi(),
      _scheduleApi = scheduleApi ?? ScheduleApi();

  static final AcademicCalendarManager instance = AcademicCalendarManager();
  static const Duration checkInterval = Duration(hours: 24);

  final CalendarApi _api;
  final ScheduleApi _scheduleApi;
  final Map<String, Future<AcademicCalendarSyncResult>> _inFlight = {};
  final Set<String> _manualRefreshTerms = {};
  final ValueNotifier<int> epoch = ValueNotifier<int>(0);
  final Map<String, AcademicCalendarSyncState> _states = {};
  bool _disposed = false;

  AcademicCalendarSyncState stateFor(String yearTerm) =>
      _states[_term(yearTerm)] ?? const AcademicCalendarSyncState.idle();

  Future<DateTime?> lastSuccessfulAtFor(String yearTerm) async {
    final prefs = await SharedPreferences.getInstance();
    return _readSuccessAt(prefs, _term(yearTerm));
  }

  Listenable get listenable => this;
  ValueListenable<int> get refreshEpoch => epoch;

  Future<AcademicCalendarSnapshot?> loadCached(String yearTerm) async {
    final prefs = await SharedPreferences.getInstance();
    final term = _term(yearTerm);
    final snapshot = _readSnapshot(prefs, term);
    if (snapshot != null && !_states.containsKey(term)) {
      _states[term] = AcademicCalendarSyncState(
        phase: AcademicCalendarSyncPhase.unchanged,
        revision: snapshot.revision,
        lastSuccessfulAt: _readSuccessAt(prefs, term),
      );
    }
    return snapshot;
  }

  Future<AcademicCalendarSyncResult> refresh(
    String yearTerm, {
    bool manual = true,
  }) {
    final term = _term(yearTerm);
    if (term.isEmpty) {
      return Future.value(
        const AcademicCalendarSyncResult(
          updated: false,
          notModified: false,
          error: FormatException('缺少当前学期'),
        ),
      );
    }
    final existing = _inFlight[term];
    if (existing != null) {
      if (manual) _manualRefreshTerms.add(term);
      return existing;
    }
    if (manual) _manualRefreshTerms.add(term);
    final future = _refreshInternal(term, manual: manual);
    _inFlight[term] = future;
    future.whenComplete(() {
      if (identical(_inFlight[term], future)) {
        _inFlight.remove(term);
        _manualRefreshTerms.remove(term);
      }
    });
    return future;
  }

  Future<AcademicCalendarSyncResult> refreshIfDue(String yearTerm) async {
    final term = _term(yearTerm);
    if (term.isEmpty) return refresh(term, manual: false);
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = prefs.getInt(_checkedAtKey(term));
    if (lastCheck != null &&
        DateTime.now().difference(
              DateTime.fromMillisecondsSinceEpoch(lastCheck),
            ) <
            checkInterval &&
        _readSnapshot(prefs, term) != null) {
      final cached = _readSnapshot(prefs, term)!;
      _setState(
        term,
        AcademicCalendarSyncState(
          phase: AcademicCalendarSyncPhase.unchanged,
          revision: cached.revision,
          lastSuccessfulAt: _readSuccessAt(prefs, term),
        ),
      );
      return const AcademicCalendarSyncResult(
        updated: false,
        notModified: true,
      );
    }
    return refresh(term, manual: false);
  }

  /// Starts a non-blocking first check for the term currently selected by the
  /// schedule cache. It intentionally does not depend on notice enhancement.
  Future<void> initializeFromPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final account = (prefs.getString('account') ?? '').trim();
      final term = account.isEmpty
          ? ''
          : (prefs.getString('schedule_last_term_$account') ??
                    prefs.getString('schedule_widget_term_$account') ??
                    '')
                .trim();
      if (term.isNotEmpty) await refreshIfDue(term);
    } catch (error, stackTrace) {
      AppLogger.I.warn(
        'AcademicCalendar',
        'initial sync failed',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<AcademicCalendarSyncResult> _refreshInternal(
    String term, {
    required bool manual,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final old = _readSnapshot(prefs, term);
    _setState(
      term,
      AcademicCalendarSyncState(
        phase: AcademicCalendarSyncPhase.loading,
        revision: old?.revision,
        lastSuccessfulAt: _readSuccessAt(prefs, term),
      ),
    );
    try {
      final response = await _api.fetch(
        yearTerm: term,
        etag: prefs.getString(_etagKey(term)),
      );
      final now = DateTime.now();
      if (response.notModified) {
        final current = old;
        if (current == null) {
          throw const FormatException('校历接口返回 304 但本地没有完整快照');
        }
        await prefs.setInt(_checkedAtKey(term), now.millisecondsSinceEpoch);
        await prefs.setInt(_successAtKey(term), now.millisecondsSinceEpoch);
        _setState(
          term,
          AcademicCalendarSyncState(
            phase: AcademicCalendarSyncPhase.unchanged,
            revision: current.revision,
            lastSuccessfulAt: now,
          ),
        );
        return AcademicCalendarSyncResult(
          updated: false,
          notModified: true,
          snapshot: current,
        );
      }
      final snapshot = response.snapshot;
      if (snapshot == null || !snapshot.complete || snapshot.yearTerm != term) {
        throw const FormatException('校历快照不完整或学期不匹配');
      }
      final changedDayCount = _changedDayCount(old, snapshot);
      await prefs.setString(_snapshotKey(term), snapshot.encode());
      await prefs.setString(_etagKey(term), response.etag ?? snapshot.revision);
      await prefs.setInt(_checkedAtKey(term), now.millisecondsSinceEpoch);
      await prefs.setInt(_successAtKey(term), now.millisecondsSinceEpoch);
      _setState(
        term,
        AcademicCalendarSyncState(
          phase: AcademicCalendarSyncPhase.success,
          revision: snapshot.revision,
          changedDayCount: changedDayCount,
          lastSuccessfulAt: now,
        ),
      );
      final revisionChanged = old?.revision != snapshot.revision;
      if (revisionChanged) epoch.value++;
      if (old != null &&
          revisionChanged &&
          !manual &&
          !_manualRefreshTerms.contains(term)) {
        await LocalNotifications.showScheduleUpdate(
          title: '假期与调休已更新',
          body: changedDayCount > 0
              ? '当前学期更新了 $changedDayCount 天安排'
              : '当前学期校历已更新',
          payload: LocalNotifications.payloadScheduleUpdate,
        );
      }
      final userId = (prefs.getString('account') ?? '').trim();
      if (userId.isNotEmpty && revisionChanged) {
        try {
          await _scheduleApi.rebuildWidgetCalendarProjection(
            userId: userId,
            yearTerm: term,
            calendar: snapshot,
          );
        } catch (projectionError, projectionStackTrace) {
          // Calendar persistence remains successful even if the optional
          // native-widget projection cannot be rebuilt from schedule cache.
          AppLogger.I.warn(
            'AcademicCalendar',
            'widget calendar projection rebuild failed',
            error: projectionError,
            stackTrace: projectionStackTrace,
            fields: {'term': term},
          );
        }
        await WidgetUpdater.updateTodayWidget(
          trigger: 'academic_calendar_refresh',
        );
        await CourseReminderScheduler.rescheduleForUser(
          userId,
          calendar: snapshot,
        );
      }
      return AcademicCalendarSyncResult(
        updated: revisionChanged,
        notModified: false,
        snapshot: snapshot,
      );
    } catch (error, stackTrace) {
      AppLogger.I.warn(
        'AcademicCalendar',
        'calendar refresh failed',
        error: error,
        stackTrace: stackTrace,
        fields: {'term': term},
      );
      _setState(
        term,
        AcademicCalendarSyncState(
          phase: AcademicCalendarSyncPhase.failure,
          errorMessage: error.toString(),
          revision: old?.revision,
          lastSuccessfulAt: _readSuccessAt(prefs, term),
        ),
      );
      return AcademicCalendarSyncResult(
        updated: false,
        notModified: false,
        snapshot: old,
        error: error,
      );
    }
  }

  static int _changedDayCount(
    AcademicCalendarSnapshot? old,
    AcademicCalendarSnapshot next,
  ) {
    if (old == null) return next.days.length;
    final before = old.byDate;
    final after = next.byDate;
    final keys = {...before.keys, ...after.keys};
    return keys
        .where(
          (key) =>
              jsonEncode(before[key]?.toJson()) !=
              jsonEncode(after[key]?.toJson()),
        )
        .length;
  }

  AcademicCalendarSnapshot? _readSnapshot(
    SharedPreferences prefs,
    String term,
  ) {
    final raw = prefs.getString(_snapshotKey(term));
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return AcademicCalendarSnapshot.fromJson(
          decoded.cast<String, dynamic>(),
        );
      }
    } catch (_) {}
    return null;
  }

  DateTime? _readSuccessAt(SharedPreferences prefs, String term) {
    final value = prefs.getInt(_successAtKey(term));
    return value == null ? null : DateTime.fromMillisecondsSinceEpoch(value);
  }

  void _setState(String term, AcademicCalendarSyncState state) {
    _states[term] = state;
    if (!_disposed) notifyListeners();
  }

  static String _term(String value) => value.trim();
  static String _snapshotKey(String term) =>
      'academic_calendar_snapshot_v1_$term';
  static String _etagKey(String term) => 'academic_calendar_etag_v1_$term';
  static String _checkedAtKey(String term) =>
      'academic_calendar_checked_at_v1_$term';
  static String _successAtKey(String term) =>
      'academic_calendar_success_at_v1_$term';

  @override
  void dispose() {
    _disposed = true;
    epoch.dispose();
    super.dispose();
  }
}
