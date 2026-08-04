import 'package:cqut_helper/api/schedule/schedule_api.dart';
import 'package:cqut_helper/model/class_schedule_model.dart';
import 'package:cqut_helper/manager/schedule_repository.dart';
import 'package:cqut_helper/model/schedule_week_change.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_recent_change_detector.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_refresh_orchestrator.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_time_info_coordinator.dart';
import 'package:cqut_helper/pages/ClassSchedule/controllers/schedule_week_loader.dart';

class ScheduleController {
  final ScheduleApi _service;
  final ScheduleRepository _repository;
  late final ScheduleTimeInfoCoordinator _timeInfoCoordinator;
  late final ScheduleWeekLoader _weekLoader;
  late final ScheduleRefreshOrchestrator _refreshOrchestrator;
  late final ScheduleRecentChangeDetector _recentChangeDetector;

  ScheduleController({ScheduleApi? service, ScheduleRepository? repository})
    : _service = service ?? repository?.api ?? ScheduleRepository.shared.api,
      _repository =
          repository ??
          (service == null
              ? ScheduleRepository.shared
              : ScheduleRepository(service)) {
    _timeInfoCoordinator = ScheduleTimeInfoCoordinator(
      service: _service,
      getTimeInfoList: () => timeInfoList,
      setTimeInfoList: (value) => timeInfoList = value,
    );
    _weekLoader = ScheduleWeekLoader(
      service: _service,
      repository: _repository,
      getWeekCache: () => weekCache,
      setWeekCache: (value) => weekCache = value,
      getCurrentTerm: () => currentTerm,
      setCurrentTerm: (value) => currentTerm = value,
      setWeekList: (value) => weekList = value,
      setActualCurrentWeekStr: (value) => actualCurrentWeekStr = value,
      setActualCurrentTermStr: (value) => actualCurrentTermStr = value,
      setNowInTeachingWeek: (value) => nowInTeachingWeek = value,
      setNowStatusLabel: (value) => nowStatusLabel = value,
    );
    _refreshOrchestrator = ScheduleRefreshOrchestrator(
      isDisposed: () => _disposed,
      ensureWeekLoaded: ensureWeekLoaded,
      loadUserId: () async {
        await _weekLoader.loadCredentials();
        return _weekLoader.userId;
      },
    );
    _recentChangeDetector = ScheduleRecentChangeDetector(
      service: _service,
      weekLoader: _weekLoader,
      getWeekCache: () => weekCache,
      isDisposed: () => _disposed,
    );
  }

  Map<int, ScheduleData> weekCache = {};
  List<CampusTimeInfo>? timeInfoList;
  String? currentTerm;
  List<String>? weekList;
  String? actualCurrentWeekStr;
  String? actualCurrentTermStr;
  bool? nowInTeachingWeek;
  String? nowStatusLabel;
  String? get userId => _weekLoader.userId;
  String? get encryptedPassword => _weekLoader.encryptedPassword;

  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _refreshOrchestrator.dispose();
  }

  void reset() {
    weekCache.clear();
    currentTerm = null;
    weekList = null;
    actualCurrentWeekStr = null;
    actualCurrentTermStr = null;
    nowInTeachingWeek = null;
    nowStatusLabel = null;
    _refreshOrchestrator.cancelPrefetch();
  }

  Future<bool> loadTimeInfoFromCacheIfAny() {
    return _timeInfoCoordinator.loadTimeInfoFromCacheIfAny();
  }

  Future<bool> isFresh(
    ScheduleData data, {
    Duration maxAge = const Duration(minutes: 15),
  }) {
    return _weekLoader.isFresh(data, maxAge: maxAge);
  }

  void hydrateCurrentStatusFromCache(ScheduleData data) {
    _weekLoader.hydrateCurrentStatusFromCache(data);
  }

  Future<void> loadCredentials() => _weekLoader.loadCredentials();

  Future<bool> refreshTimeInfoIfEnabled({bool force = false}) {
    return _timeInfoCoordinator.refreshTimeInfoIfEnabled(force: force);
  }

  Future<void> ensureTimeInfoLoaded() {
    return _timeInfoCoordinator.ensureTimeInfoLoaded(
      isDisposed: () => _disposed,
    );
  }

  Future<ScheduleData?> loadFromCache({String? weekNum, String? yearTerm}) {
    return _weekLoader.loadFromCache(weekNum: weekNum, yearTerm: yearTerm);
  }

  Future<int> reloadMemoryCacheFromDisk({required String yearTerm}) {
    return _weekLoader.reloadMemoryCacheFromDisk(yearTerm: yearTerm);
  }

  Future<ScheduleData> loadFromNetwork({
    String? weekNum,
    String? yearTerm,
    bool persistLastViewed = true,
    bool updateWidgetPins = false,
  }) {
    return _weekLoader.loadFromNetwork(
      weekNum: weekNum,
      yearTerm: yearTerm,
      persistLastViewed: persistLastViewed,
      updateWidgetPins: updateWidgetPins,
    );
  }

  Future<void> invalidateCachedWeeks({
    required String userId,
    required String yearTerm,
    required Iterable<int> weeks,
  }) async {
    final affected = weeks.toSet();
    for (final week in affected) {
      weekCache.remove(week);
    }
    await _service.invalidateCachedWeeks(
      userId: userId,
      yearTerm: yearTerm,
      weeks: affected,
    );
  }

  Future<void> deleteCustomEvent({
    required String userId,
    required String encryptedPassword,
    required String eventId,
  }) {
    return _service.deleteCustomEvent(
      userId: userId,
      encryptedPassword: encryptedPassword,
      eventId: eventId,
    );
  }

  bool processLoadedData(ScheduleData data) {
    return _weekLoader.processLoadedData(data);
  }

  void schedulePrefetch(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    _refreshOrchestrator.schedulePrefetch(currentData, onUpdate, delay: delay);
  }

  Future<List<ScheduleWeekChange>> silentCheckRecentWeeksForChangesDetailed(
    ScheduleData currentData, {
    int weeksAhead = 1,
    int maxDiffLinesPerWeek = 30,
  }) {
    return _recentChangeDetector.silentCheckRecentWeeksForChangesDetailed(
      currentData,
      weeksAhead: weeksAhead,
      maxDiffLinesPerWeek: maxDiffLinesPerWeek,
    );
  }

  Future<void> refreshAllWeeksInForeground(
    ScheduleData currentData, {
    Duration interval = const Duration(seconds: 2),
  }) {
    return _refreshOrchestrator.refreshAllWeeksInForeground(
      currentData,
      interval: interval,
    );
  }

  void prefetchAllWeeksInBackground(
    ScheduleData currentData,
    Function() onUpdate, {
    Duration interval = const Duration(milliseconds: 150),
    bool forceRefresh = false,
  }) {
    _refreshOrchestrator.prefetchAllWeeksInBackground(
      currentData,
      onUpdate,
      interval: interval,
      forceRefresh: forceRefresh,
    );
  }

  Future<bool> ensureWeekLoaded(
    String weekNum,
    String yearTerm, {
    bool forceRefresh = false,
    bool updateLastViewed = false,
  }) {
    return _weekLoader.ensureWeekLoaded(
      weekNum,
      yearTerm,
      forceRefresh: forceRefresh,
      updateLastViewed: updateLastViewed,
    );
  }
}
