import 'dart:convert';

import 'package:cqut_helper/api/exam/exam_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/exam_reminder_scheduler.dart';
import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:cqut_helper/model/exam_model.dart';
import 'package:cqut_helper/utils/keyed_snapshot_diff.dart';
import 'package:cqut_helper/utils/local_notifications.dart';
import 'package:cqut_helper/utils/widget_updater.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExamRepository extends ChangeNotifier {
  ExamRepository({
    ExamApi? api,
    CredentialStore? credentialStore,
    Future<void> Function()? updateWidgets,
    Future<void> Function(String title, String body)? notifyExamChange,
    Future<void> Function(String userId, List<ExamRecord> exams)?
    rescheduleExams,
    Future<SharedPreferences> Function()? prefsProvider,
  }) : _api = api ?? ExamApi(),
       _credentials = credentialStore ?? CredentialStore(),
       _prefsProvider = prefsProvider ?? SharedPreferences.getInstance,
       _updateWidgets =
           updateWidgets ??
           (() async {
             await WidgetUpdater.updateTodayWidget(trigger: 'exam_refresh');
           }),
       _notifyExamChange =
           notifyExamChange ??
           ((String title, String body) =>
               LocalNotifications.showScheduleUpdate(title: title, body: body)),
       _rescheduleExams =
           rescheduleExams ??
           ((String userId, List<ExamRecord> exams) =>
               ExamReminderScheduler.rescheduleForUser(userId, exams: exams));
  static final ExamRepository instance = ExamRepository();
  static const maxAge = Duration(minutes: 30);
  static Future<void> _cacheWrites = Future<void>.value();
  static const _sessionEpochKey = 'exam_session_epoch';
  static String cacheKey(String account) => 'exam_cache_v1_${account.trim()}';
  final ExamApi _api;
  final CredentialStore _credentials;
  final Future<SharedPreferences> Function() _prefsProvider;
  final Future<void> Function() _updateWidgets;
  final Future<void> Function(String title, String body) _notifyExamChange;
  final Future<void> Function(String userId, List<ExamRecord> exams)
  _rescheduleExams;
  String? _account;
  int _generation = 0;
  Future<ExamSnapshot?>? _pending;
  ExamSnapshot? _snapshot;
  Object? _error;
  bool get refreshing => _pending != null;
  ExamSnapshot? get snapshot => _snapshot;
  List<ExamRecord> get exams => _snapshot?.exams ?? const [];
  Object? get error => _error;
  bool get requiresReauthentication => _error is ExamAuthenticationException;

  /// Reads this account's cache; refresh is explicit so callers can render it first.
  Future<ExamSnapshot?> load() async {
    final prefs = await _prefsProvider();
    await prefs.reload();
    final account = (prefs.getString('account') ?? '').trim();
    if (_account != account) {
      _generation++;
      _account = account;
      _snapshot = null;
      _error = null;
      _pending = null;
    }
    if (account.isEmpty) {
      notifyListeners();
      return null;
    }
    final raw = prefs.getString(cacheKey(account));
    ExamSnapshot? cached;
    if (raw != null) {
      try {
        cached = ExamSnapshot.fromJson(
          (jsonDecode(raw) as Map).cast<String, dynamic>(),
        );
      } catch (_) {}
    }
    if (cached != null &&
        (_snapshot == null || cached.fetchedAt.isAfter(_snapshot!.fetchedAt))) {
      _error = null;
    }
    _snapshot = cached;
    notifyListeners();
    return cached;
  }

  /// Deduplicated across pages; returns cached data on failure and exposes [error].
  Future<ExamSnapshot?> refresh({bool force = false}) async {
    final prefs = await _prefsProvider();
    await prefs.reload();
    final account = (prefs.getString('account') ?? '').trim();
    if (account.isEmpty) {
      invalidate();
      return null;
    }
    if (_account == account && _pending != null) return _pending;
    await load();
    if (_account != account) return null;
    if (_pending != null) return _pending;
    if (!force &&
        _snapshot != null &&
        DateTime.now().difference(_snapshot!.fetchedAt) < maxAge) {
      return _snapshot;
    }
    final generation = _generation;
    final request = _fetch(account, generation);
    _pending = request;
    notifyListeners();
    try {
      return await request;
    } finally {
      if (generation == _generation) {
        _pending = null;
        notifyListeners();
      }
    }
  }

  Future<ExamSnapshot?> _fetch(String account, int generation) async {
    final previousSnapshot = _snapshot;
    int? requestEpoch;
    try {
      final initialPrefs = await _prefsProvider();
      await initialPrefs.reload();
      final sessionEpoch = initialPrefs.getInt(_sessionEpochKey) ?? 0;
      requestEpoch = sessionEpoch;
      if (generation != _generation ||
          (initialPrefs.getString('account') ?? '').trim() != account) {
        return null;
      }
      final password = await _credentials.readEncryptedPassword();
      if (password == null || password.isEmpty) {
        throw const ExamAuthenticationException();
      }
      final baseUrl = await ScheduleSettingsManager.loadNoticeApiBaseUrl();
      await initialPrefs.reload();
      if (generation != _generation ||
          (initialPrefs.getInt(_sessionEpochKey) ?? 0) != sessionEpoch ||
          (initialPrefs.getString('account') ?? '').trim() != account) {
        if (generation == _generation) await load();
        return null;
      }
      final result = await _api.fetch(
        baseUrl: baseUrl,
        username: account,
        encryptedPassword: password,
      );
      final prefs = await _prefsProvider();
      await prefs.reload();
      if (generation != _generation ||
          (prefs.getString('account') ?? '').trim() != account ||
          (prefs.getInt(_sessionEpochKey) ?? 0) != sessionEpoch) {
        if (generation == _generation) await load();
        return null;
      }
      var persisted = false;
      final write = _cacheWrites.then((_) async {
        await prefs.reload();
        if (generation != _generation ||
            (prefs.getInt(_sessionEpochKey) ?? 0) != sessionEpoch ||
            (prefs.getString('account') ?? '').trim() != account) {
          return;
        }
        await prefs.setString(cacheKey(account), jsonEncode(result.toJson()));
        persisted = true;
      });
      _cacheWrites = write.catchError((Object _) {});
      await write;
      if (!persisted || generation != _generation) return null;
      await prefs.reload();
      if ((prefs.getInt(_sessionEpochKey) ?? 0) != sessionEpoch ||
          (prefs.getString('account') ?? '').trim() != account) {
        await load();
        return null;
      }
      _snapshot = result;
      _error = null;
      notifyListeners();
      if (previousSnapshot != null) {
        try {
          final message = buildChangeMessage(
            previousSnapshot.exams,
            result.exams,
          );
          if (message != null) {
            await _notifyExamChange('考试安排更新', message);
          }
        } catch (error, stackTrace) {
          AppLogger.I.warn(
            'ExamRepository',
            'exam change notification failed',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      try {
        await _rescheduleExams(account, result.exams);
      } catch (error, stackTrace) {
        AppLogger.I.warn(
          'ExamRepository',
          'exam reminder reschedule failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
      try {
        await _updateWidgets();
      } catch (error, stackTrace) {
        AppLogger.I.warn(
          'ExamRepository',
          'widget update failed after exam persistence',
          error: error,
          stackTrace: stackTrace,
        );
      }
      return result;
    } catch (error) {
      final prefs = await _prefsProvider();
      await prefs.reload();
      if (requestEpoch != null &&
          (prefs.getInt(_sessionEpochKey) ?? 0) != requestEpoch) {
        if (generation == _generation) await load();
        return null;
      }
      if ((prefs.getString('account') ?? '').trim() != account) {
        if (generation == _generation) await load();
        return null;
      }
      if (generation == _generation) {
        _error = error;
        notifyListeners();
      }
      return generation == _generation ? _snapshot : null;
    }
  }

  /// Returns null when nothing changed; a single-line message otherwise.
  @visibleForTesting
  static String? buildChangeMessage(
    List<ExamRecord> previous,
    List<ExamRecord> current,
  ) {
    final diff = diffByKey<ExamRecord>(
      previous: previous,
      current: current,
      keyOf: (e) => e.key,
      differs: (a, b) =>
          a.courseName != b.courseName ||
          a.timeText != b.timeText ||
          a.startAt != b.startAt ||
          a.endAt != b.endAt ||
          a.campus != b.campus ||
          a.building != b.building ||
          a.room != b.room,
    );
    if (!diff.hasChanges) return null;

    final parts = <String>[];
    if (diff.added.isNotEmpty) parts.add('新增 ${diff.added.length} 门');
    if (diff.removed.isNotEmpty) parts.add('取消 ${diff.removed.length} 门');
    if (diff.changed.isNotEmpty) parts.add('变更 ${diff.changed.length} 门');

    final names = <String>{
      ...diff.added.map((e) => e.courseName),
      ...diff.removed.map((e) => e.courseName),
      ...diff.changed.map((e) => e.courseName),
    }.take(3).toList();
    final totalAffected =
        diff.added.length + diff.removed.length + diff.changed.length;
    final detail = names.join('、');
    final detailSuffix = names.length < totalAffected ? ' 等' : '';
    return '${parts.join('，')}$detailSuffix：$detail';
  }

  /// Invalidates in-flight writes before account cache removal.
  void invalidate({String? account}) {
    if (account != null && _account != account.trim()) return;
    _generation++;
    _pending = null;
    _snapshot = null;
    _error = null;
    _account = null;
    notifyListeners();
  }

  static Future<void> clearAccountCache(String account) {
    instance.invalidate(account: account);
    final clear = _cacheWrites.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      await prefs.setInt(
        _sessionEpochKey,
        (prefs.getInt(_sessionEpochKey) ?? 0) + 1,
      );
      await prefs.remove(cacheKey(account));
    });
    _cacheWrites = clear.catchError((Object _) {});
    return clear.then((_) async {
      await WidgetUpdater.updateTodayWidget(trigger: 'exam_cache_clear');
    });
  }
}
