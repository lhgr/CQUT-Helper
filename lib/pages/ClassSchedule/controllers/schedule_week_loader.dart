import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/manager/credential_store.dart';
import 'package:cqut_helper/manager/schedule_repository.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:cqut_helper/utils/schedule_date.dart';
import 'package:cqut_helper/utils/schedule_fingerprint_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    _userId = prefs.getString('account');
    _encryptedPassword = await credentialStore.readEncryptedPassword();
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
    _userId ??= prefs.getString('account');

    final userId = _userId;
    if (userId == null || userId.isEmpty) return null;

    return service.loadFromCache(
      userId: userId,
      weekNum: weekNum,
      yearTerm: yearTerm,
    );
  }

  Future<ScheduleData> loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
  }) async {
    await loadCredentials();

    if (_userId == null || _userId!.isEmpty) {
      throw Exception('未登录');
    }
    if (_encryptedPassword == null || _encryptedPassword!.isEmpty) {
      throw Exception('凭证已过期，请重新登录');
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
      persistLastViewed: persistLastViewed,
      updateWidgetPins: shouldPinWidget,
    );
    final loadedWeek = (data.weekNum ?? '').trim();
    final loadedWeeks = data.weekList;
    if (loadedWeek.isEmpty || loadedWeeks == null || loadedWeeks.isEmpty) {
      throw Exception('课表鉴权失败，请重新登录');
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
  }) async {
    final wInt = int.tryParse(weekNum) ?? 0;
    final cache = getWeekCache();

    if (!forceRefresh) {
      if (cache.containsKey(wInt)) return true;

      final cached = await loadFromCache(weekNum: weekNum, yearTerm: yearTerm);
      if (cached != null) {
        cache[wInt] = cached;
        return true;
      }
    }

    try {
      final data = await loadFromNetwork(
        weekNum: weekNum,
        yearTerm: yearTerm,
        persistLastViewed: updateLastViewed,
        updateWidgetPins: false,
      );
      processLoadedData(data);
      final uid = _userId;
      final term = (data.yearTerm ?? yearTerm).trim();
      final week = (data.weekNum ?? weekNum).trim();
      if (uid != null && uid.isNotEmpty && term.isNotEmpty && week.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        final fpKey = fingerprintKey(uid, term, week);
        final fpUpdatedAtKey = fingerprintUpdatedAtKey(uid, term, week);
        final fetchAtKey = lastFetchAtKey(uid, term, week);
        final now = DateTime.now().millisecondsSinceEpoch;
        final fp = scheduleFingerprintFromScheduleData(data);
        await prefs.setString(fpKey, fp);
        await prefs.setInt(fpUpdatedAtKey, now);
        await prefs.setInt(fetchAtKey, now);
      }
      return true;
    } catch (e, st) {
      AppLogger.I.event(
        LogLevel.debug,
        'ScheduleController',
        event: 'schedule_week_prefetch_fail',
        messageZh: '预取周课表失败，已忽略',
        message: 'prefetch week failed',
        module: 'schedule',
        action: 'prefetch_week',
        status: 'fail',
        reason: 'prefetch_failed',
        error: e,
        stackTrace: st,
        fields: {'week': weekNum, 'term': yearTerm},
      );
      return false;
    }
  }
}
