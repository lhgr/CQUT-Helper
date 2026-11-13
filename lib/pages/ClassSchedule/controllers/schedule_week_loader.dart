import 'dart:convert';

import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_repository.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:cqut_helper/utils/schedule_fingerprint_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

class _ScheduleCredentialsUnavailable implements Exception {
  _ScheduleCredentialsUnavailable(this.message);
  final String message;
  @override
  String toString() => 'Exception: $message';
}

class _WeekLoadResult {
  const _WeekLoadResult.success() : error = null, stackTrace = null;
  const _WeekLoadResult.failure(this.error, this.stackTrace);

  final Object? error;
  final StackTrace? stackTrace;
  bool get loaded => error == null;
}

class ScheduleWeekLoader {
  final ScheduleApi service;
  final CredentialStore credentialStore;
  final ScheduleRepository repository;
  final Map<int, ScheduleData> Function() getWeekCache;
  final void Function(Map<int, ScheduleData> value) setWeekCache;
  final String? Function() getCurrentTerm;
  final void Function(String? value) setCurrentTerm;
  final void Function(List<String>? value) setWeekList;
  final void Function(String? value) setActualCurrentWeekStr;
  final void Function(String? value) setActualCurrentTermStr;
  final void Function(bool? value) setNowInTeachingWeek;
  final void Function(String? value) setNowStatusLabel;
  String? _userId;
  String? _encryptedPassword;
  int _scopeVersion = 0;
  int _selectionVersion = 0;

  int get selectionVersion => _selectionVersion;

  void invalidateRequests() {
    _scopeVersion++;
    _selectionVersion++;
    _weekLoadRequests.clear();
  }

  void selectWeek(String? weekNum, String? yearTerm) {
    _selectionVersion++;
    final term = yearTerm?.trim();
    if (term != null && term.isNotEmpty && getCurrentTerm() != term) {
      _scopeVersion++;
      _weekLoadRequests.clear();
      getWeekCache().clear();
      setWeekList(null);
      setCurrentTerm(term);
    }
  }

  String? _syncAccount(SharedPreferences prefs) {
    final account = prefs.getString('account')?.trim();
    if (_userId != null && _userId != account) {
      invalidateRequests();
      getWeekCache().clear();
      setCurrentTerm(null);
      setWeekList(null);
      setActualCurrentWeekStr(null);
      setActualCurrentTermStr(null);
    }
    _userId = account;
    return account;
  }

  bool _isCurrent(int scope, String? account) =>
      scope == _scopeVersion && account == _userId;

  Future<bool> _isCurrentAccount(int scope, String? account) async {
    final prefs = await SharedPreferences.getInstance();
    _syncAccount(prefs);
    return _isCurrent(scope, account);
  }

  Future<void> _persistSelection(
    ScheduleData data,
    int selection,
    int scope,
    String? account,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    _syncAccount(prefs);
    if (!_isCurrent(scope, account) ||
        selection != _selectionVersion ||
        account == null ||
        account.isEmpty) {
      return;
    }
    final week = (data.weekNum ?? '').trim();
    final term = (data.yearTerm ?? '').trim();
    if (week.isEmpty || term.isEmpty) return;
    // Queue both writes together so a later selection writes after this one.
    await Future.wait([
      prefs.setString('schedule_last_week_$account', week),
      prefs.setString('schedule_last_term_$account', term),
    ]);
  }

  Future<void> rememberSelection(ScheduleData data) =>
      _persistSelection(data, _selectionVersion, _scopeVersion, _userId);
  final Map<String, Future<_WeekLoadResult>> _weekLoadRequests = {};

  ScheduleWeekLoader({
    required this.service,
    ScheduleRepository? repository,
    CredentialStore? credentialStore,
    required this.getWeekCache,
    required this.setWeekCache,
    required this.getCurrentTerm,
    required this.setCurrentTerm,
    required this.setWeekList,
    required this.setActualCurrentWeekStr,
    required this.setActualCurrentTermStr,
    required this.setNowInTeachingWeek,
    required this.setNowStatusLabel,
  }) : credentialStore = credentialStore ?? CredentialStore(),
       repository = repository ?? ScheduleRepository(service);

  Future<void> loadCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final account = _syncAccount(prefs);
    final scope = _scopeVersion;
    final password = await credentialStore.readEncryptedPassword();
    if (!await _isCurrentAccount(scope, account)) {
      throw DioException(
        requestOptions: RequestOptions(path: '/schedule'),
        type: DioExceptionType.cancel,
      );
    }
    _encryptedPassword = password;
    _hydrateCurrentAnchorFromPreferences(prefs, account);
  }

  String? get userId => _userId;
  String? get encryptedPassword => _encryptedPassword;

  String fingerprintKey(String userId, String yearTerm, String weekNum) =>
      'schedule_fp_${userId}_${yearTerm}_$weekNum';

  String fingerprintUpdatedAtKey(
    String userId,
    String yearTerm,
    String weekNum,
  ) => 'schedule_fp_updated_at_${userId}_${yearTerm}_$weekNum';

  String lastFetchAtKey(String userId, String yearTerm, String weekNum) =>
      'schedule_fetch_at_${userId}_${yearTerm}_$weekNum';

  Future<ScheduleData?> loadFromCache({
    String? weekNum,
    String? yearTerm,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _syncAccount(prefs);

    final userId = _userId;
    if (userId == null || userId.isEmpty) return null;
    _hydrateCurrentAnchorFromPreferences(prefs, userId);

    final scope = _scopeVersion;
    final data = await service.loadFromCache(
      userId: userId,
      weekNum: weekNum,
      yearTerm: yearTerm,
      waitForSideEffects: false,
    );
    return await _isCurrentAccount(scope, userId) ? data : null;
  }

  void _hydrateCurrentAnchorFromPreferences(
    SharedPreferences prefs,
    String? userId,
  ) {
    final normalizedUserId = (userId ?? '').trim();
    if (normalizedUserId.isEmpty) return;
    final week = prefs
        .getString('schedule_widget_week_$normalizedUserId')
        ?.trim();
    final term = prefs
        .getString('schedule_widget_term_$normalizedUserId')
        ?.trim();
    if (week == null || week.isEmpty || term == null || term.isEmpty) return;
    setActualCurrentWeekStr(week);
    setActualCurrentTermStr(term);
  }

  Future<int> reloadMemoryCacheFromDisk({required String yearTerm}) async {
    final normalizedTerm = yearTerm.trim();
    if (normalizedTerm.isEmpty) return 0;
    final scope = _scopeVersion;
    final cache = getWeekCache();
    final weeks = cache.entries
        .where((entry) => (entry.value.yearTerm ?? '').trim() == normalizedTerm)
        .map((entry) => entry.key)
        .toList(growable: false);
    var refreshedCount = 0;
    for (final week in weeks) {
      final refreshed = await loadFromCache(
        weekNum: week.toString(),
        yearTerm: normalizedTerm,
      );
      if (scope != _scopeVersion ||
          (getCurrentTerm() != null && getCurrentTerm() != normalizedTerm)) {
        return refreshedCount;
      }
      if (refreshed == null ||
          (refreshed.yearTerm ?? '').trim() != normalizedTerm) {
        continue;
      }
      cache[week] = refreshed;
      refreshedCount++;
    }
    return refreshedCount;
  }

  Future<ScheduleData> loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
    String trigger = 'schedule_load',
    bool waitForSideEffects = true,
    bool refreshReminders = true,
    bool select = true,
  }) {
    if (select) selectWeek(weekNum, yearTerm);
    final selection = _selectionVersion;
    final scope = _scopeVersion;
    return AppLogger.I.runWithTraceIdAsync(
      AppLogger.I.currentTraceId ?? AppLogger.I.newTraceId(),
      () async {
        final elapsed = Stopwatch()..start();
        try {
          final data = await _loadFromNetwork(
            weekNum: weekNum,
            yearTerm: yearTerm,
            persistLastViewed: persistLastViewed,
            updateWidgetPins: updateWidgetPins,
            selection: selection,
            scope: scope,
            waitForSideEffects: waitForSideEffects,
            refreshReminders: refreshReminders,
          );
          AppLogger.I.logOperationOutcome(
            'ScheduleWeekLoader',
            'week load finished',
            outcome: 'succeeded',
            fields: {
              'stage': 'load_week',
              'trigger': trigger,
              'data_source': 'network',
              'network_outcome': 'succeeded',
              'week': weekNum,
              'term': yearTerm,
              'duration_ms': elapsed.elapsedMilliseconds,
            },
          );
          return data;
        } catch (error, stackTrace) {
          if (error is! _ScheduleCredentialsUnavailable &&
              !(error is DioException &&
                  error.type == DioExceptionType.cancel)) {
            AppLogger.I.logOperationOutcome(
              'ScheduleWeekLoader',
              'week load failed',
              outcome: 'failed',
              error: error,
              stackTrace: stackTrace,
              fields: {
                'stage': 'load_week',
                'trigger': trigger,
                'duration_ms': elapsed.elapsedMilliseconds,
                'week': weekNum,
                'term': yearTerm,
              },
            );
          }
          rethrow;
        }
      },
    );
  }

  Future<ScheduleData> _loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
    required int selection,
    required int scope,
    required bool waitForSideEffects,
    required bool refreshReminders,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accountChanged =
        _userId != null && _userId != prefs.getString('account')?.trim();
    if (accountChanged) {
      final stillSelected = selection == _selectionVersion;
      _syncAccount(prefs);
      if (!stillSelected) {
        throw DioException(
          requestOptions: RequestOptions(path: '/schedule'),
          type: DioExceptionType.cancel,
        );
      }
      selectWeek(weekNum, yearTerm);
      scope = _scopeVersion;
      selection = _selectionVersion;
    }
    await loadCredentials();
    final account = _userId;
    if (scope != _scopeVersion) {
      throw DioException(
        requestOptions: RequestOptions(path: "/schedule"),
        type: DioExceptionType.cancel,
      );
    }

    if (_userId == null || _userId!.isEmpty) {
      AppLogger.I.info(
        'ScheduleWeekLoader',
        'schedule load skipped while signed out',
        fields: const {
          'stage': 'validate_credentials',
          'outcome': 'skip_not_logged_in',
        },
      );
      throw _ScheduleCredentialsUnavailable('未登录');
    }
    if (_encryptedPassword == null || _encryptedPassword!.isEmpty) {
      AppLogger.I.info(
        'ScheduleWeekLoader',
        'schedule load requires credentials',
        fields: const {
          'stage': 'validate_credentials',
          'outcome': 'skip_missing_credentials',
        },
      );
      throw _ScheduleCredentialsUnavailable('凭证已过期，请重新登录');
    }

    final shouldPinWidget =
        updateWidgetPins ||
        ((weekNum == null || weekNum.trim().isEmpty) &&
            (yearTerm == null || yearTerm.trim().isEmpty));
    final data = await repository.loadFromNetwork(
      userId: _userId!,
      encryptedPassword: _encryptedPassword!,
      weekNum: weekNum,
      yearTerm: yearTerm,
      persistLastViewed: false,
      updateWidgetPins: shouldPinWidget,
      waitForSideEffects: waitForSideEffects,
      refreshReminders: refreshReminders,
    );
    final loadedWeek = (data.weekNum ?? '').trim();
    final loadedWeeks = data.weekList;
    if (loadedWeek.isEmpty || loadedWeeks == null || loadedWeeks.isEmpty) {
      final error = Exception('课表鉴权失败，请重新登录');
      AppLogger.I.logOperationFailure(
        'ScheduleWeekLoader',
        'schedule week metadata is invalid',
        error: error,
        stackTrace: StackTrace.current,
        fields: {
          'stage': 'validate_schedule',
          'outcome': 'rejected',
          'reason': 'missing_week_metadata',
          'week': weekNum,
          'term': yearTerm,
          'weekMissing': loadedWeek.isEmpty,
          'weekListMissing': loadedWeeks == null || loadedWeeks.isEmpty,
        },
      );
      throw error;
    }

    if (!await _isCurrentAccount(scope, account)) {
      throw DioException(
        requestOptions: RequestOptions(path: "/schedule"),
        type: DioExceptionType.cancel,
      );
    }
    if (persistLastViewed) {
      await _persistSelection(data, selection, scope, account);
    }
    if (weekNum == null && yearTerm == null) {
      final now = DateTime.now();
      if (ScheduleDate.dataCoversDate(data, now)) {
        setNowInTeachingWeek(true);
        setNowStatusLabel(null);
        setActualCurrentWeekStr(data.weekNum);
        setActualCurrentTermStr(data.yearTerm);
      } else {
        setNowInTeachingWeek(false);
        setActualCurrentWeekStr(data.weekNum);
        setActualCurrentTermStr(data.yearTerm);
      }
    }

    return data;
  }

  Future<bool> isFresh(
    ScheduleData data, {
    Duration maxAge = const Duration(minutes: 15),
  }) {
    return repository.isFresh(data, maxAge: maxAge);
  }

  bool processLoadedData(ScheduleData data) {
    if (data.weekNum == null || data.weekList == null) return false;

    final cache = getWeekCache();
    var termChanged = false;
    if (getCurrentTerm() != data.yearTerm) {
      cache.clear();
      termChanged = true;
    }
    setCurrentTerm(data.yearTerm);
    setWeekList(data.weekList);

    final weekNum = int.tryParse(data.weekNum!) ?? 1;
    cache[weekNum] = data;
    return termChanged;
  }

  void hydrateCurrentStatusFromCache(ScheduleData data) {
    if (!ScheduleDate.dataCoversDate(data, DateTime.now())) return;
    setNowInTeachingWeek(true);
    setNowStatusLabel(null);
    setActualCurrentWeekStr(data.weekNum);
    setActualCurrentTermStr(data.yearTerm);
  }

  Future<bool> ensureWeekLoaded(
    String weekNum,
    String yearTerm, {
    bool forceRefresh = false,
    bool updateLastViewed = false,
    bool rethrowOnFailure = false,
    bool refreshReminders = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    _syncAccount(prefs);
    if (updateLastViewed) selectWeek(weekNum, yearTerm);
    final term = getCurrentTerm();
    if (term != null && term != yearTerm.trim()) return false;
    final scope = _scopeVersion;
    final account = _userId;
    final selection = _selectionVersion;
    final requestKey = [
      account,
      scope,
      if (updateLastViewed) selection,
      yearTerm.trim(),
      weekNum.trim(),
      forceRefresh,
      updateLastViewed,
      refreshReminders,
    ].join('|');
    final existing = _weekLoadRequests[requestKey];
    final request =
        existing ??
        AppLogger.I.runWithTraceIdAsync(
          AppLogger.I.currentTraceId ?? AppLogger.I.newTraceId(),
          () => _ensureWeekLoadedInternal(
            weekNum,
            yearTerm,
            forceRefresh: forceRefresh,
            updateLastViewed: updateLastViewed,
            scope: scope,
            account: account,
            selection: selection,
            refreshReminders: refreshReminders,
          ),
        );
    _weekLoadRequests[requestKey] = request;
    try {
      final result = await request;
      final error = result.error;
      if (error != null && rethrowOnFailure) {
        // A shared request explicitly supplies the same cause to every waiter.
        AppLogger.I.linkFailure(error, error);
        Error.throwWithStackTrace(
          error,
          result.stackTrace ?? StackTrace.current,
        );
      }
      return result.loaded;
    } finally {
      if (identical(_weekLoadRequests[requestKey], request)) {
        _weekLoadRequests.remove(requestKey);
      }
    }
  }

  Future<_WeekLoadResult> _ensureWeekLoadedInternal(
    String weekNum,
    String yearTerm, {
    required bool forceRefresh,
    required bool updateLastViewed,
    required int scope,
    required String? account,
    required int selection,
    required bool refreshReminders,
  }) async {
    final wInt = int.tryParse(weekNum) ?? 0;
    final cache = getWeekCache();

    if (!forceRefresh) {
      final existing = cache[wInt];
      if (existing != null && existing.yearTerm == yearTerm) {
        if (updateLastViewed) {
          await _persistSelection(existing, selection, scope, account);
        }
        return const _WeekLoadResult.success();
      }

      final cached = await loadFromCache(weekNum: weekNum, yearTerm: yearTerm);
      if (!await _isCurrentAccount(scope, account)) {
        return _WeekLoadResult.failure(
          StateError('课表请求已取消'),
          StackTrace.current,
        );
      }
      if (cached != null && cached.yearTerm == yearTerm) {
        cache[wInt] = cached;
        if (updateLastViewed) {
          await _persistSelection(cached, selection, scope, account);
        }
        return const _WeekLoadResult.success();
      }
    }

    try {
      final data = await loadFromNetwork(
        weekNum: weekNum,
        yearTerm: yearTerm,
        persistLastViewed: false,
        updateWidgetPins: false,
        trigger: 'ensure_week_loaded',
        select: false,
        waitForSideEffects: false,
        refreshReminders: refreshReminders,
      );
      if (!await _isCurrentAccount(scope, account)) {
        return _WeekLoadResult.failure(
          StateError('课表请求已取消'),
          StackTrace.current,
        );
      }
      processLoadedData(data);
      if (updateLastViewed) {
        await _persistSelection(data, selection, scope, account);
      }
      final uid = _userId;
      final term = (data.yearTerm ?? yearTerm).trim();
      final week = (data.weekNum ?? weekNum).trim();
      if (uid != null && uid.isNotEmpty && term.isNotEmpty && week.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final fpKey = fingerprintKey(uid, term, week);
        final fpUpdatedAtKey = fingerprintUpdatedAtKey(uid, term, week);
        final fetchAtKey = lastFetchAtKey(uid, term, week);
        final now = DateTime.now().millisecondsSinceEpoch;
        var fp = scheduleFingerprintFromScheduleData(data);
        try {
          final raw = await service.getCachedScheduleJson(
            userId: uid,
            yearTerm: term,
            weekNum: week,
          );
          if (raw != null && raw.trim().isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              fp = scheduleFingerprintFromWeekJsonMap(
                decoded.cast<String, dynamic>(),
              );
            }
          }
        } catch (_) {
          // The fingerprint computed from the returned model remains valid;
          // an optional cache re-read must not turn a successful fetch into a
          // failed week load.
        }
        await prefs.setString(fpKey, fp);
        await prefs.setInt(fpUpdatedAtKey, now);
        await prefs.setInt(fetchAtKey, now);
      }
      return const _WeekLoadResult.success();
    } catch (e, st) {
      if (e is _ScheduleCredentialsUnavailable ||
          (e is DioException && e.type == DioExceptionType.cancel)) {
        AppLogger.I.info(
          'ScheduleController',
          'prefetch skipped',
          fields: {
            'stage': 'prefetch_week',
            'outcome': e is DioException
                ? 'cancelled'
                : 'skip_missing_credentials',
            'week': weekNum,
            'term': yearTerm,
          },
        );
        return _WeekLoadResult.failure(e, st);
      }
      AppLogger.I.logOperationOutcome(
        'ScheduleController',
        'prefetch week failed',
        outcome: 'failed',
        error: e,
        stackTrace: st,
        fields: {
          'stage': 'prefetch_week',
          'reason': 'prefetch_failed',
          'week': weekNum,
          'term': yearTerm,
        },
      );
      return _WeekLoadResult.failure(e, st);
    }
  }
}
